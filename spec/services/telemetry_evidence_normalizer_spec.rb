# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryEvidenceNormalizer do
  it "records an exact source time and replaces client-spoofed server evidence" do
    received_at = Time.zone.parse("2026-08-09T12:00:00Z")
    occurred_at = Time.zone.parse("2026-08-08T10:30:00Z")

    result = described_class.normalize(
      context: {
        "platform" => "android",
        "telemetry_schema_version" => 3,
        "sdk" => { "name" => "logister-android", "version" => "0.4.0" },
        "diagnostic" => { "source" => "sdk", "kind" => "crash" },
        "error" => { "fatal" => true },
        "telemetry_evidence" => {
          "source" => "spoofed",
          "time" => { "received_at" => "1999-01-01T00:00:00Z" }
        }
      },
      client_occurred_at: occurred_at,
      received_at: received_at
    )
    evidence = result.evidence

    expect(result.canonical_occurred_at).to eq(occurred_at)
    expect(evidence).to include(
      "schema_version" => 1,
      "source" => "sdk",
      "kind" => "crash",
      "evidence_kind" => "crashed_stack",
      "identity_scope" => "occurrence",
      "fatality" => "fatal"
    )
    expect(evidence.fetch("time")).to eq(
      "precision" => "exact",
      "occurred_at" => "2026-08-08T10:30:00.000000Z",
      "received_at" => "2026-08-09T12:00:00.000000Z"
    )
    expect(evidence.fetch("producer")).to include(
      "sdk_name" => "logister-android",
      "sdk_version" => "0.4.0",
      "telemetry_schema_version" => 3
    )
    expect(evidence.dig("normalization", "owner")).to eq("server")
  end

  it "uses a reporting boundary without inventing an exact MetricKit occurrence time" do
    result = described_class.normalize(
      context: {
        "platform" => "ios",
        "diagnostic" => {
          "source" => "metrickit",
          "kind" => "hang",
          "reporting_period" => {
            "start" => "2026-08-01T00:00:00Z",
            "end" => "2026-08-02T00:00:00Z"
          }
        }
      },
      client_occurred_at: nil,
      received_at: Time.zone.parse("2026-08-09T12:00:00Z")
    )

    expect(result.canonical_occurred_at).to eq(Time.zone.parse("2026-08-02T00:00:00Z"))
    expect(result.evidence.fetch("time")).to include(
      "precision" => "reporting_interval",
      "reporting_start" => "2026-08-01T00:00:00.000000Z",
      "reporting_end" => "2026-08-02T00:00:00.000000Z",
      "received_at" => "2026-08-09T12:00:00.000000Z"
    )
    expect(result.evidence.dig("time", "occurred_at")).to be_nil
    expect(result.evidence["evidence_kind"]).to eq("sampled_call_tree")
  end

  it "marks evidence received-only when the source provides no event time or report interval" do
    received_at = Time.zone.parse("2026-08-09T12:00:00Z")
    result = described_class.normalize(
      context: { "platform" => "ios", "diagnostic" => { "source" => "metrickit", "kind" => "cpu_exception" } },
      client_occurred_at: nil,
      received_at: received_at
    )

    expect(result.canonical_occurred_at).to eq(received_at)
    expect(result.evidence.fetch("time")).to eq(
      "precision" => "received_only",
      "received_at" => "2026-08-09T12:00:00.000000Z"
    )
  end
end
