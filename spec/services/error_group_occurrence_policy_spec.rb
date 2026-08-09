# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorGroupOccurrencePolicy do
  let(:project) { create(:project) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }

  def evidence_context(precision:, occurred_at: nil, reporting_start: nil, reporting_end: nil, received_at: Time.current)
    {
      "telemetry_evidence" => {
        "schema_version" => 1,
        "source" => "sdk",
        "kind" => "crash",
        "evidence_kind" => "crashed_stack",
        "identity_scope" => "occurrence",
        "fatality" => "fatal",
        "time" => {
          "precision" => precision,
          "occurred_at" => occurred_at&.utc&.iso8601(6),
          "reporting_start" => reporting_start&.utc&.iso8601(6),
          "reporting_end" => reporting_end&.utc&.iso8601(6),
          "received_at" => received_at.utc.iso8601(6)
        }.compact
      }
    }
  end

  it "counts exact historical evidence without reopening a group closed later" do
    closure_time = 1.day.ago
    original_latest = create(:ingest_event, project: project, api_key: api_key, occurred_at: 3.days.ago)
    group = create(
      :error_group,
      project: project,
      status: :resolved,
      resolved_at: closure_time,
      occurrence_count: 1,
      latest_event_id: original_latest.id,
      latest_event_occurred_at: original_latest.occurred_at,
      first_seen_at: original_latest.occurred_at,
      last_seen_at: original_latest.occurred_at
    )
    historical_time = 2.days.ago
    event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      occurred_at: historical_time,
      context: evidence_context(precision: "exact", occurred_at: historical_time)
    )

    decision = group.record_occurrence_with_policy!(event)

    expect(decision).not_to be_reopen_group
    expect(decision).not_to be_workflow_alerts
    expect(decision.reason).to eq(:source_evidence_before_closure)
    expect(group.reload).to be_resolved
    expect(group.occurrence_count).to eq(2)
    expect(group.latest_event_id).to eq(event.id)
    expect(group.last_seen_at).to eq(historical_time)
    expect(group.regression_count).to eq(0)
  end

  it "does not reopen or replace source chronology for received-only evidence" do
    closure_time = 1.hour.ago
    original_latest = create(:ingest_event, project: project, api_key: api_key, occurred_at: 2.hours.ago)
    group = create(
      :error_group,
      project: project,
      status: :resolved,
      resolved_at: closure_time,
      occurrence_count: 1,
      latest_event_id: original_latest.id,
      latest_event_occurred_at: original_latest.occurred_at,
      first_seen_at: original_latest.occurred_at,
      last_seen_at: original_latest.occurred_at
    )
    event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      occurred_at: Time.current,
      context: evidence_context(precision: "received_only")
    )

    decision = group.record_occurrence_with_policy!(event)

    expect(decision.reason).to eq(:received_only)
    expect(decision).not_to be_reopen_group
    expect(decision).not_to be_update_latest
    expect(group.reload).to be_resolved
    expect(group.latest_event_id).to eq(original_latest.id)
    expect(group.last_seen_at).to eq(original_latest.occurred_at)
    expect(group.occurrence_count).to eq(2)
  end

  it "reopens only when a reporting interval starts after the group was closed" do
    closure_time = 2.hours.ago
    original_latest = create(:ingest_event, project: project, api_key: api_key, occurred_at: 3.hours.ago)
    group = create(
      :error_group,
      project: project,
      status: :resolved,
      resolved_at: closure_time,
      occurrence_count: 1,
      latest_event_id: original_latest.id,
      latest_event_occurred_at: original_latest.occurred_at,
      first_seen_at: original_latest.occurred_at,
      last_seen_at: original_latest.occurred_at
    )
    reporting_start = 1.hour.ago
    reporting_end = 30.minutes.ago
    event = create(
      :ingest_event,
      project: project,
      api_key: api_key,
      occurred_at: reporting_end,
      context: evidence_context(
        precision: "reporting_interval",
        reporting_start: reporting_start,
        reporting_end: reporting_end
      )
    )

    decision = group.record_occurrence_with_policy!(event)

    expect(decision).to be_reopen_group
    expect(decision).to be_workflow_alerts
    expect(group.reload).to be_unresolved
    expect(group.first_seen_at).to eq(original_latest.occurred_at)
    expect(group.last_seen_at).to eq(reporting_end)
    expect(group.reopen_count).to eq(1)
    expect(group.regression_count).to eq(1)
    expect(group.current_regression).to include(
      "schema_version" => 1,
      "reason" => "after_resolved",
      "policy_reason" => "source_evidence_after_closure",
      "time_precision" => "reporting_interval",
      "proof_at" => reporting_start.utc.iso8601(6),
      "closure_at" => closure_time.utc.iso8601(6),
      "event_uuid" => event.uuid
    )
  end

  it "clears automatic regression evidence when a closed group is manually reopened" do
    group = create(
      :error_group,
      project: project,
      status: :resolved,
      resolved_at: 1.hour.ago,
      regression_count: 1,
      current_regression: { "reason" => "after_resolved", "proof_at" => 2.hours.ago.iso8601 }
    )

    group.reopen!

    expect(group.reload.current_regression).to eq({})
    expect(group.regression_count).to eq(1)
  end
end
