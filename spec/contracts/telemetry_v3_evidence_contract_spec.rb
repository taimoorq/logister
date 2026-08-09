# frozen_string_literal: true

require "rails_helper"

RSpec.describe "telemetry v3 evidence contract" do
  FIXTURES = %w[
    telemetry_v3_android_exact.json
    telemetry_v3_android_anr.json
    telemetry_v3_ios_reporting_interval.json
  ].freeze

  it "publishes a parseable additive schema with immutable identity and evidence fields" do
    schema = JSON.parse(Rails.root.join("docs/telemetry_v3_evidence.schema.json").read)

    expect(schema).to include("$schema" => "https://json-schema.org/draft/2020-12/schema")
    expect(schema.fetch("required")).to contain_exactly("uuid", "event_type", "message")
    expect(schema.dig("properties", "evidence", "additionalProperties")).to be(false)
    expect(schema.dig("properties", "context", "additionalProperties")).to be(true)
  end

  it "keeps the canonical OpenAPI ingest schema aligned with the standalone evidence schema" do
    standalone = JSON.parse(Rails.root.join("docs/telemetry_v3_evidence.schema.json").read)
    openapi = YAML.safe_load_file(Rails.root.join("docs/openapi.yaml"), aliases: false)
    schemas = openapi.dig("components", "schemas")

    expect(schemas.dig("IngestEvent", "properties", "evidence", "$ref")).to eq(
      "#/components/schemas/TelemetryEvidence"
    )
    expect(schemas.dig("TelemetryEvidence", "properties").keys).to contain_exactly(
      *standalone.dig("properties", "evidence", "properties").keys
    )
    expect(schemas.dig("TelemetryEvidence", "additionalProperties")).to be(false)
    expect(schemas.dig("TelemetryReportingPeriod", "required")).to contain_exactly("start", "end")
  end

  FIXTURES.each do |fixture_name|
    it "normalizes #{fixture_name} to its golden server evidence" do
      fixture = JSON.parse(Rails.root.join("spec/fixtures/files", fixture_name).read)
      params = ActionController::Parameters.new(event: fixture.fetch("input"))
      payload = IngestEventPayloadNormalizer.new(params:, default_environment: nil)
      event_hash = payload.event_hash
      attributes = payload.event_params(event_hash)
      result = TelemetryEvidenceNormalizer.normalize(
        context: attributes.fetch("context"),
        client_occurred_at: attributes["occurred_at"],
        received_at: fixture.fetch("received_at")
      )

      expect(result.evidence).to eq(fixture.fetch("expected_evidence"))
    end
  end
end
