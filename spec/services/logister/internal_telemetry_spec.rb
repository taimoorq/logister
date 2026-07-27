# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::InternalTelemetry do
  it "marks automatic notification job failures" do
    payload = {
      event_type: "error",
      context: { job: { jobClass: "ProjectErrorFirstOccurrenceAlertJob" } }
    }

    described_class.enrich_payload(payload)

    expect(payload.dig(:context, described_class::CONTEXT_KEY)).to include(
      "component" => "notifications",
      "operation" => "job_failure",
      "feedback_depth" => 1
    )
  end

  it "marks automatic ClickHouse job failures" do
    payload = { context: { job: { jobClass: "ClickhouseIngestJob" } } }

    described_class.enrich_payload(payload)

    expect(described_class.component(payload[:context])).to eq("clickhouse")
  end

  it "preserves explicit provenance and increments causation depth" do
    source = create(:ingest_event, context: {
      "logister_internal" => { "component" => "notifications", "feedback_depth" => 1 }
    })

    context = described_class.with_origin({}, component: "clickhouse", operation: "event_ingest_failure", caused_by: source)

    expect(described_class.metadata(context)).to include(
      "component" => "clickhouse",
      "operation" => "event_ingest_failure",
      "feedback_depth" => 2,
      "caused_by_uuid" => source.uuid
    )
  end
end
