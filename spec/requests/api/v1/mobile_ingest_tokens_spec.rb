# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::MobileIngestTokens", type: :request do
  before do
    allow(Logister).to receive(:report_log).and_return(true)
  end

  let(:project) { create(:project, :android, user: users(:one)) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }
  let(:server_headers) { { "Authorization" => "Bearer #{api_key.plain_token}" } }

  describe "POST /api/v1/mobile_ingest_tokens" do
    it "mints a short-lived mobile ingest token with a server API key" do
      expect {
        post api_v1_mobile_ingest_tokens_path,
             params: {
               mobile_ingest_token: {
                 platform: "android",
                 service: "com.example.app",
                 environment: "production",
                 release: "1.4.0+42",
                 session_id: "session-123",
                 expires_in_seconds: 900,
                 allowed_event_types: [ "error", "log" ]
               }
             },
             as: :json,
             headers: server_headers
      }.to change(MobileIngestToken, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["token"]).to start_with("logister_mobile_")
      expect(body["platform"]).to eq("android")
      expect(body["service"]).to eq("com.example.app")
      expect(body["allowed_event_types"]).to eq([ "error", "log" ])

      token = MobileIngestToken.find_by!(token_digest: MobileIngestToken.digest(body["token"]))
      expect(token.project).to eq(project)
      expect(token.api_key).to eq(api_key)
      expect(token.expires_at).to be_within(2.seconds).of(900.seconds.from_now)
      expect(api_key.reload.last_used_at).to be_present
    end

    it "rejects mobile tokens for nonmatching project platforms" do
      post api_v1_mobile_ingest_tokens_path,
           params: {
             mobile_ingest_token: {
               platform: "ios",
               service: "com.example.app",
               environment: "production"
             }
           },
           as: :json,
           headers: server_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].join).to include("Platform must match")
    end

    it "rejects unsupported event scopes" do
      post api_v1_mobile_ingest_tokens_path,
           params: {
             mobile_ingest_token: {
               platform: "android",
               service: "com.example.app",
               environment: "production",
               allowed_event_types: [ "error", "deployment" ]
             }
           },
           as: :json,
           headers: server_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].join).to include("deployment")
    end

    it "rejects overly long mobile token lifetimes" do
      post api_v1_mobile_ingest_tokens_path,
           params: {
             mobile_ingest_token: {
               platform: "android",
               service: "com.example.app",
               environment: "production",
               expires_in_seconds: 7_200
             }
           },
           as: :json,
           headers: server_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].join).to include("Expires at must be within")
    end

    it "rejects missing token envelopes" do
      post api_v1_mobile_ingest_tokens_path,
           params: { token: { platform: "android" } },
           as: :json,
           headers: server_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("mobile_ingest_token")
    end

    it "does not allow mobile ingest tokens to mint more tokens" do
      mobile_token = create(:mobile_ingest_token, project: project, api_key: api_key)

      post api_v1_mobile_ingest_tokens_path,
           params: {
             mobile_ingest_token: {
               platform: "android",
               service: "com.example.app",
               environment: "production"
             }
           },
           as: :json,
           headers: { "Authorization" => "Bearer #{mobile_token.plain_token}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("Forbidden")
    end
  end
end
