# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectNotificationEvidence do
  it "uses the triggering mobile occurrence instead of the group's globally latest occurrence" do
    project = create(:project, :ios)
    group = create(:error_group, project: project)
    metric_event = create(:ingest_event, project: project, occurred_at: 2.days.ago)
    latest_event = create(:ingest_event, project: project, occurred_at: 1.minute.ago)
    metric_occurrence = create(
      :error_occurrence,
      error_group: group,
      ingest_event: metric_event,
      occurred_at: metric_event.occurred_at,
      dimensions: {
        "evidence_source" => "metrickit",
        "diagnostic_kind" => "hang",
        "build_number" => "42",
        "distribution_channel" => "TestFlight",
        "symbolication_status" => "artifact_matched",
        "time_precision" => "reporting_interval"
      }
    )
    create(
      :error_occurrence,
      error_group: group,
      ingest_event: latest_event,
      occurred_at: latest_event.occurred_at,
      dimensions: {
        "evidence_source" => "sdk",
        "diagnostic_kind" => "reported_error",
        "build_number" => "43",
        "time_precision" => "exact"
      }
    )

    metadata = described_class.enrich(
      project: project,
      error_group: group,
      metadata: { "event_id" => metric_event.id, "occurred_at" => metric_event.occurred_at.iso8601 }
    )

    expect(metadata).to include(
      "evidence_source" => "metrickit",
      "diagnostic_kind" => "hang",
      "build_number" => "42",
      "distribution_channel" => "TestFlight",
      "artifact_state" => "artifact_matched",
      "time_precision" => "reporting_interval"
    )
    expect(described_class.event_for(error_group: group, metadata: metadata)).to eq(metric_occurrence.ingest_event_record)
  end
end
