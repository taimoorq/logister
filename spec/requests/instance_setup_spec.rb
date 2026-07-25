# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Instance setup", type: :request do
  around do |example|
    original = ENV["LOGISTER_SETUP_TOKEN"]
    ENV["LOGISTER_SETUP_TOKEN"] = "a-long-one-time-setup-token"
    Installation.delete_all
    example.run
  ensure
    ENV["LOGISTER_SETUP_TOKEN"] = original
  end

  it "creates, confirms, signs in, and persists the first administrator" do
    expect do
      post instance_setup_path, params: {
        setup_token: "a-long-one-time-setup-token",
        user: {
          name: "First Operator",
          email: "operator@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end.to change(User, :count).by(1)

    operator = User.find_by!(email: "operator@example.com")
    installation = Installation.current
    expect(operator).to be_confirmed
    expect(operator).to be_application_admin
    expect(installation).to be_claimed
    expect(installation).to be_onboarding_required
    expect(installation.claimed_by_user).to eq(operator)
    expect(response).to redirect_to(admin_installation_section_path("general"))

    follow_redirect!
    expect(response.body).to include("General", "Canonical URLs and instance identity")
  end

  it "does not store or accept an incorrect setup token" do
    post instance_setup_path, params: {
      setup_token: "incorrect",
      user: {
        email: "attacker@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("one-time setup token is invalid")
    expect(response.body).not_to include("a-long-one-time-setup-token")
    expect(User.find_by(email: "attacker@example.com")).to be_nil
    expect(Installation.current_if_available&.claimed?).not_to be(true)
  end

  it "routes ordinary signup to the first-admin setup while the token is active" do
    get new_user_registration_path

    expect(response).to redirect_to(instance_setup_path)
  end

  it "closes the claim path after an administrator has claimed the instance" do
    installation = Installation.current
    operator = create(:user, application_admin: true)
    installation.claim!(operator)

    get instance_setup_path

    expect(response).to redirect_to(new_user_session_path)
  end
end
