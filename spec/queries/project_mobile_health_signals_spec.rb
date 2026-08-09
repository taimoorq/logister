# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectMobileHealthSignals do
  let(:now) { Time.zone.parse("2026-08-09 12:00:00 UTC") }

  it "reports observed artifact gaps and failed distribution sources without inventing client loss" do
    project = create(:project, :android)
    group = create(:error_group, project: project)
    event = create(:ingest_event, project: project, occurred_at: now - 1.hour, created_at: now - 1.hour)
    create(
      :error_occurrence,
      error_group: group,
      ingest_event: event,
      occurred_at: event.occurred_at,
      created_at: event.created_at,
      dimensions: { "mapping_status" => "missing" }
    )
    create(
      :project_integration_setting,
      project: project,
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.shop",
      credential_reference: "GOOGLE_PLAY_CREDENTIALS",
      last_imported_at: now - 2.days,
      metadata: { "last_error" => { "message" => "permission denied", "at" => (now - 1.hour).iso8601 } }
    )

    signals = described_class.new(project, now: now).call.index_by(&:kind)

    expect(signals.keys).to contain_exactly("mobile_artifact_health", "mobile_source_health")
    expect(signals.fetch("mobile_artifact_health").metadata).to include(
      "state" => "unconfigured",
      "evidence_count" => 1,
      "recovery_action" => include("mapping.txt")
    )
    expect(signals.fetch("mobile_source_health").metadata).to include(
      "state" => "failed",
      "reason" => include("latest Google Play import failed")
    )
  end

  it "requires a sustained receipt baseline before reporting intake silence" do
    project = create(:project, :ios)
    4.times do |day|
      5.times do |event_index|
        received_at = now - (day + 3).days - event_index.minutes
        create(:ingest_event, :log, project: project, occurred_at: received_at, created_at: received_at)
      end
    end

    signal = described_class.new(project, now: now).call.find { |candidate| candidate.kind == "mobile_intake_health" }

    expect(signal).to be_present
    expect(signal.metadata).to include(
      "state" => "stale",
      "baseline_event_count" => 20,
      "baseline_active_days" => 4,
      "recovery_action" => include("does not prove client queue loss")
    )
  end

  it "keeps new, low-volume, and currently receiving projects quiet" do
    new_project = create(:project, :android)
    low_volume = create(:project, :ios)
    active = create(:project, :android)
    create(:ingest_event, :log, project: low_volume, occurred_at: now - 3.days, created_at: now - 3.days)
    create(:ingest_event, :log, project: active, occurred_at: now - 1.hour, created_at: now - 1.hour)

    expect(described_class.new(new_project, now: now).call).to be_empty
    expect(described_class.new(low_volume, now: now).call).to be_empty
    expect(described_class.new(active, now: now).call).to be_empty
  end
end
