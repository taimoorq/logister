# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CLI device authorization", type: :request do
  let(:user) { create(:user) }
  let!(:project) { create(:project, user: user, name: "Checkout API", slug: "checkout-api") }

  it "approves a browser-backed CLI login and exchanges it for a read token" do
    post "/api/v1/cli/device_authorizations", params: { client_name: "Logister CLI" }

    expect(response).to have_http_status(:created)
    authorization_payload = response.parsed_body
    expect(authorization_payload["device_code"]).to be_present
    expect(authorization_payload["user_code"]).to match(/\A[A-Z0-9]{4}-[A-Z0-9]{4}\z/)
    expect(authorization_payload["verification_uri"]).to end_with("/cli/device")
    expect(authorization_payload["verification_uri_complete"]).to include("user_code=")

    post "/api/v1/cli/device_authorizations/token", params: { device_code: authorization_payload["device_code"] }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("authorization_pending")

    sign_in user
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
end
