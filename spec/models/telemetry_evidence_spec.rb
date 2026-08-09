# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryEvidence do
  it "reads the server-normalized contract with explicit clock semantics" do
    event = Struct.new(:context, :occurred_at, :created_at).new(
      {
        "telemetry_evidence" => {
          "schema_version" => 1,
          "source" => "metrickit",
          "kind" => "hang",
          "capture_mode" => "metrickit",
          "evidence_kind" => "sampled_call_tree",
          "identity_scope" => "occurrence",
          "fatality" => "nonfatal",
          "time" => {
            "precision" => "reporting_interval",
            "reporting_start" => "2026-08-01T00:00:00Z",
            "reporting_end" => "2026-08-02T00:00:00Z",
            "received_at" => "2026-08-09T12:00:00Z"
          }
        }
      },
      nil,
      nil
    )

    evidence = described_class.for(event)

    expect(evidence).to be_reporting_interval
    expect(evidence).not_to be_exact_time
    expect(evidence.operational_at).to eq(Time.zone.parse("2026-08-09T12:00:00Z"))
    expect(evidence).to have_attributes(source: "metrickit", kind: "hang", fatality: "nonfatal")
  end

  it "labels old events unknown instead of claiming their stored timestamp is exact" do
    occurred_at = Time.zone.parse("2026-07-01T12:00:00Z")
    received_at = Time.zone.parse("2026-07-02T12:00:00Z")
    event = Struct.new(:context, :occurred_at, :created_at).new(
      { "platform" => "ios", "diagnostic" => { "source" => "sdk", "kind" => "reported_error" } },
      occurred_at,
      received_at
    )

    evidence = described_class.for(event)

    expect(evidence).to have_attributes(
      schema_version: 0,
      source: "sdk",
      time_precision: "unknown",
      occurred_at: occurred_at,
      received_at: received_at
    )
  end
end
