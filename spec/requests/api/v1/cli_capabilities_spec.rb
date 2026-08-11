# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Cli::Capabilities", type: :request do
  describe "GET /api/v1/cli/capabilities" do
    it "returns public CLI compatibility metadata without authentication" do
      get "/api/v1/cli/capabilities"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      body = response.parsed_body
      expect(body).to include(
        "server" => "logister",
        "server_version" => "3.6.3",
        "api_contract_version" => "3.6.3",
        "minimum_cli_version" => "0.1.0",
        "recommended_cli_version" => "0.1.2"
      )
      expect(body["api_contract_sha256"]).to match(/\A[0-9a-f]{64}\z/)
      expect(body["features"]).to include(
        "capabilities" => true,
        "cli_access_tokens" => true,
        "device_authorization" => true,
        "projects" => true,
        "events" => true,
        "error_groups" => true,
        "ai_context_bundles" => true
      )
      expect(body["auth"]).to include(
        "cli_access_tokens" => true,
        "device_authorization" => true,
        "project_ingest_keys_for_read" => false
      )
      expect(body["endpoints"]).to include(
        "device_authorizations" => "/api/v1/cli/device_authorizations",
        "device_token" => "/api/v1/cli/device_authorizations/token"
      )
    end

    it "fails closed when an activation flag is misspelled" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("LOGISTER_CLI_FEATURE_TRACES", "false").and_return("flase")

      get "/api/v1/cli/capabilities"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("features", "traces")).to be(false)
    end
  end
end
