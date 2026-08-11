# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Health", type: :request do
  around do |example|
    config = Rails.configuration.x.logister
    original_mode = config.clickhouse_mode
    original_enabled = config.clickhouse_enabled
    example.run
  ensure
    config.clickhouse_mode = original_mode
    config.clickhouse_enabled = original_enabled
  end

  describe "GET /health/release" do
    around do |example|
      original_release = ENV["LOGISTER_RELEASE"]
      original_git_sha = ENV["LOGISTER_GIT_SHA"]
      original_image_digest = ENV["LOGISTER_IMAGE_DIGEST"]
      ENV.delete("LOGISTER_RELEASE")
      ENV.delete("LOGISTER_GIT_SHA")
      ENV.delete("LOGISTER_IMAGE_DIGEST")
      example.run
    ensure
      ENV["LOGISTER_RELEASE"] = original_release
      ENV["LOGISTER_GIT_SHA"] = original_git_sha
      ENV["LOGISTER_IMAGE_DIGEST"] = original_image_digest
    end

    it "returns the public packaged release and contract identity" do
      get "/health/release"

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-cache")
      expect(response.parsed_body).to include(
        "status" => "ok",
          "version" => "3.6.1",
          "tag" => "v3.6.1",
        "git_sha" => "unknown",
        "image_digest" => "unknown",
        "database" => { "connected" => true, "migrations_current" => true }
      )
      expect(response.parsed_body.fetch("contract_sha256").keys).to contain_exactly("cli_api", "integration_discovery", "telemetry_ingest")
    end

    it "fails closed when configured deployment metadata disagrees with the package" do
      ENV["LOGISTER_RELEASE"] = "v9.9"

      get "/health/release"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to include(
        "status" => "degraded",
        "errors" => include("configured release does not match the packaged version")
      )
    end
  end

  describe "GET /health/clickhouse" do
    context "when ClickHouse is disabled" do
      before do
        Rails.configuration.x.logister.clickhouse_mode = "disabled"
        Rails.configuration.x.logister.clickhouse_enabled = false
      end

      it "returns 200 with status disabled" do
        get "/health/clickhouse"
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["status"]).to eq("disabled")
        expect(body["clickhouse_enabled"]).to eq(false)
      end
    end

    context "when ClickHouse is enabled and healthy" do
      before do
        Rails.configuration.x.logister.clickhouse_mode = "dual_write"
        Rails.configuration.x.logister.clickhouse_enabled = true
        client = instance_double(
          Logister::ClickhouseClient,
          close: nil,
          schema_status: {
            enabled: true,
            ready: true
          }
        )
        allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
      end

      it "returns 200 with status ok" do
        get "/health/clickhouse"
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["status"]).to eq("ok")
        expect(body["clickhouse_enabled"]).to eq(true)
        expect(body["clickhouse_ready"]).to eq(true)
      end
    end

    context "when ClickHouse is enabled but unhealthy" do
      before do
        Rails.configuration.x.logister.clickhouse_mode = "dual_write"
        Rails.configuration.x.logister.clickhouse_enabled = true
        client = instance_double(
          Logister::ClickhouseClient,
          close: nil,
          schema_status: {
            enabled: true,
            healthy: true,
            ready: false,
            database: "logister",
            missing_tables: [ "spans_raw" ],
            present_tables: [ "events_raw" ],
            event_type_columns: { "events_raw" => "Enum8('error' = 1, 'metric' = 2)" },
            schema_issues: [ "events_raw.event_type uses an outdated enum" ]
          }
        )
        allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
      end

      it "returns 503 with status degraded" do
        get "/health/clickhouse"
        expect(response).to have_http_status(:service_unavailable)
        body = response.parsed_body
        expect(body["status"]).to eq("degraded")
        expect(body["clickhouse_enabled"]).to eq(true)
        expect(body["clickhouse_ready"]).to eq(false)
        expect(body.dig("schema", "missing_tables")).to eq([ "spans_raw" ])
        expect(body.dig("schema", "schema_issues")).to eq([ "events_raw.event_type uses an outdated enum" ])
      end
    end
  end
end
