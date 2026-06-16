# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Devise rate limits", type: :request do
  let(:rate_limit_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(rate_limit_cache)
  end

  after do
    rate_limit_cache.clear
  end

  it "limits sign-in attempts by IP address" do
    10.times do
      post user_session_path, params: sign_in_params

      expect(response).not_to have_http_status(:too_many_requests)
    end

    post user_session_path, params: sign_in_params

    expect_rate_limited(retry_after: 1.minute)
  end

  it "limits sign-up attempts by IP address" do
    5.times do |index|
      post user_registration_path, params: sign_up_params("signup-#{index}@example.com")

      expect(response).not_to have_http_status(:too_many_requests)
    end

    post user_registration_path, params: sign_up_params("signup-limited@example.com")

    expect_rate_limited(retry_after: 1.minute)
  end

  it "limits password reset requests by normalized email address" do
    [ "reset@example.com", " RESET@example.com ", "Reset@Example.com" ].each do |email|
      post user_password_path, params: email_params(email)

      expect(response).not_to have_http_status(:too_many_requests)
    end

    post user_password_path, params: email_params("reset@example.com")

    expect_rate_limited(retry_after: 10.minutes)
  end

  it "limits confirmation resend requests by normalized email address" do
    [ "confirm@example.com", " CONFIRM@example.com ", "Confirm@Example.com" ].each do |email|
      post user_confirmation_path, params: email_params(email)

      expect(response).not_to have_http_status(:too_many_requests)
    end

    post user_confirmation_path, params: email_params("confirm@example.com")

    expect_rate_limited(retry_after: 10.minutes)
  end

  private

  def expect_rate_limited(retry_after:)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq(retry_after.to_i.to_s)
    expect(response.body).to include(DeviseRateLimitGuard::RATE_LIMIT_MESSAGE)
  end

  def sign_in_params
    {
      user: {
        email: "nobody@example.com",
        password: "wrong-password"
      }
    }
  end

  def sign_up_params(email)
    {
      user: {
        email: email,
        password: "short",
        password_confirmation: "short"
      }
    }
  end

  def email_params(email)
    {
      user: {
        email: email
      }
    }
  end
end
