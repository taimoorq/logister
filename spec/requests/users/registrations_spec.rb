# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User registration policy", type: :request do
  let(:password) { "correct-horse-battery-staple" }

  around do |example|
    keys = %w[LOGISTER_REGISTRATION_MODE LOGISTER_REGISTRATION_ALLOWED_DOMAINS LOGISTER_SETUP_TOKEN]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def configure_registration(mode, domains: nil)
    values = { "authentication.registration_mode" => mode }
    values["authentication.registration_allowed_domains"] = domains if domains
    InstanceConfiguration.save_section!("authentication", values: values, clear_keys: [], actor: users(:one))
  end

  def sign_up(email)
    post user_registration_path, params: { "cf-turnstile-response" => "mocked", user: { name: "New User", email: email, password: password, password_confirmation: password } }
  end

  it "keeps sign-up open by default" do
    get new_user_session_path
    expect(response.body).to include(new_user_registration_path)

    expect { sign_up("open@example.com") }.to change(User, :count).by(1)
  end

  context "when registration is closed" do
    before { configure_registration("closed") }

    it "redirects the sign-up page and refuses new accounts" do
      get new_user_registration_path

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to include("Account sign-up is not available")

      expect { sign_up("closed@example.com") }.not_to change(User, :count)
      expect(response).to redirect_to(new_user_session_path)
    end

    it "hides sign-up links from the sign-in page and public pages" do
      get new_user_session_path
      expect(response.body).not_to include(new_user_registration_path)

      get root_path
      expect(response.body).not_to include(new_user_registration_path)

      get about_path
      expect(response.body).not_to include(new_user_registration_path)
    end

    it "can be closed through the environment" do
      InstanceSetting.where(key: "authentication.registration_mode").delete_all
      ENV["LOGISTER_REGISTRATION_MODE"] = "closed"

      get new_user_registration_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it "still lets the first administrator complete instance setup" do
      ENV["LOGISTER_SETUP_TOKEN"] = "a-long-one-time-setup-token"
      Installation.delete_all

      get new_user_registration_path
      expect(response).to redirect_to(instance_setup_path)

      expect do
        post instance_setup_path, params: {
          setup_token: "a-long-one-time-setup-token",
          user: { name: "First Operator", email: "operator@example.com", password: password, password_confirmation: password }
        }
      end.to change(User, :count).by(1)
      expect(User.find_by!(email: "operator@example.com")).to be_application_admin
    end
  end

  context "when registration is limited to allowed domains" do
    before { configure_registration("allowed_domains", domains: "example.com, @Example.org") }

    it "accepts addresses on an allowed domain" do
      get new_user_registration_path
      expect(response).to have_http_status(:ok)

      expect { sign_up("Person@EXAMPLE.org") }.to change(User, :count).by(1)
    end

    it "rejects other domains and subdomains with a form error" do
      expect { sign_up("person@other.test") }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("is not on a domain that can sign up on this instance")

      expect { sign_up("person@sub.example.com") }.not_to change(User, :count)
      expect { sign_up("person@example.com@other.test") }.not_to change(User, :count)
    end

    it "treats an empty domain list as closed" do
      InstanceSetting.where(key: "authentication.registration_allowed_domains").delete_all

      get new_user_registration_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
