# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CLI device authorization", type: :request do
  let(:user) { create(:user) }
  let!(:project) { create(:project, user: user, name: "Checkout API", slug: "checkout-api") }

  it "approves a browser-backed CLI login and exchanges it for a read token" do
    post "/api/v1/cli/device_authorizations",
         params: { client_name: "Logister CLI", scopes: CliAccessToken::READ_SCOPES }

    expect(response).to have_http_status(:created)
    authorization_payload = response.parsed_body
    expect(authorization_payload["device_code"]).to be_present
    expect(authorization_payload["user_code"]).to match(/\A[A-Z0-9]{4}-[A-Z0-9]{4}\z/)
    expect(authorization_payload["verification_uri"]).to end_with("/cli/device")
    expect(authorization_payload["verification_uri_complete"]).to include("user_code=")
    expect(authorization_payload["scopes"]).to eq(CliAccessToken::READ_SCOPES)
    expect(authorization_payload["scope"].split).to eq(CliAccessToken::READ_SCOPES)

    post "/api/v1/cli/device_authorizations/token", params: { device_code: authorization_payload["device_code"] }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("authorization_pending")

    sign_in user
    get "/cli/device", params: { user_code: authorization_payload["user_code"] }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("traces:read", "metrics:read", "Requested read access")

    post "/cli/device",
         params: {
           user_code: authorization_payload["user_code"],
           decision: "approve",
           project_ids: [ project.id.to_s ]
         }

    expect(response).to redirect_to("/cli/device?user_code=#{authorization_payload['user_code']}")

    post "/api/v1/cli/device_authorizations/token", params: { device_code: authorization_payload["device_code"] }

    expect(response).to have_http_status(:ok)
    token_payload = response.parsed_body
    expect(token_payload["access_token"]).to start_with("logister_cli_")
    expect(token_payload["token_type"]).to eq("Bearer")
    expect(token_payload["scope"].split).to match_array(CliAccessToken::READ_SCOPES)
    expect(token_payload["scopes"]).to eq(CliAccessToken::READ_SCOPES)

    get "/api/v1/cli/projects", headers: { "Authorization" => "Bearer #{token_payload['access_token']}" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["items"].pluck("slug")).to eq([ "checkout-api" ])
  end

  it "lets a signed-in user deny a CLI login request" do
    authorization = create(:cli_device_authorization)

    sign_in user
    post "/cli/device", params: { user_code: authorization.user_code_display, decision: "deny" }

    expect(response).to redirect_to("/cli/device?user_code=#{authorization.user_code_display}")
    expect(authorization.reload).to be_denied
  end

  it "rejects expired or unknown device codes during polling" do
    expired = create(:cli_device_authorization, :expired, device_code: "expired-device-code")

    post "/api/v1/cli/device_authorizations/token", params: { device_code: "expired-device-code" }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("expired_token")

    post "/api/v1/cli/device_authorizations/token", params: { device_code: "missing-device-code" }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("invalid_grant")

    expect(expired.reload.cli_access_token).to be_nil
  end

  it "rate limits device creation by hashed IP and fails open on cache outage" do
    cache = ActiveSupport::Cache::MemoryStore.new
    allow(Rails.application.config.x.logister).to receive(:rate_limit_cache).and_return(cache)
    stub_const("Api::V1::Cli::DeviceRateLimitGuard::CREATE_LIMIT", 1)

    post "/api/v1/cli/device_authorizations", params: { client_name: "first" }
    expect(response).to have_http_status(:created)

    post "/api/v1/cli/device_authorizations", params: { client_name: "second" }
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body["code"]).to eq("rate_limited")
    expect(cache.instance_variable_get(:@data).keys.join).not_to include(request.remote_ip.to_s)

    unavailable = Class.new do
      def increment(*)
        raise "cache unavailable"
      end
    end.new
    allow(Rails.application.config.x.logister).to receive(:rate_limit_cache).and_return(unavailable)

    post "/api/v1/cli/device_authorizations", params: { client_name: "fail open" }
    expect(response).to have_http_status(:created)
  end
end
