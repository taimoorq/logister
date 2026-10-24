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

  it "keeps limiting sign-in attempts through the in-process fallback when the rate-limit store is unavailable" do
    allow(Rails).to receive(:cache).and_return(unavailable_rate_limit_store)
    degraded = []
    subscriber = ActiveSupport::Notifications.subscribe(Logister::RateLimitCounter::DEGRADED_EVENT) { |*, payload| degraded << payload }

    10.times do
      post user_session_path, params: sign_in_params

      expect(response).not_to have_http_status(:too_many_requests)
    end

    post user_session_path, params: sign_in_params

    expect_rate_limited(retry_after: 1.minute)
    expect(degraded).to include(hash_including(kind: "devise_ip-short", fallback: "memory"))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it "fails closed for Devise create actions when no rate-limit store can count" do
    allow(Rails).to receive(:cache).and_return(unavailable_rate_limit_store)
    break_rate_limit_fallback_store!

    # The first prepended rule to run rejects the request, so Retry-After is
    # that rule's window.
    post user_session_path, params: sign_in_params
    expect_rate_limited(retry_after: 10.minutes)

    expect {
      post user_registration_path, params: sign_up_params("outage@example.com")
    }.not_to change(User, :count)
    expect_rate_limited(retry_after: 1.hour)
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
