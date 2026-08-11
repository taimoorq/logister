# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ProjectRetentionRunCoordinator, type: :model do
  let(:scheduled_for) { Time.zone.parse("2026-08-11 02:00:00") }

  it "persists immutable policy and cutoff snapshots" do
    project = create(:project)
    create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 60,
      error_retention_days: 90,
      archive_enabled: true,
      archive_before_delete: true
    )

    outcome = described_class.create_or_find!(
      project: project,
      scheduled_for: scheduled_for,
      dry_run: false,
      trigger_kind: "scheduled"
    )

    expect(outcome.created).to be(true)
    expect(outcome.run.policy_snapshot).to include(
      "hot_retention_days" => 30,
      "trace_retention_days" => 60,
      "archive_enabled" => true
    )
    expect(outcome.run.cutoff_snapshot).to include(
      "hot_events" => (scheduled_for - 30.days).utc.iso8601(6),
      "trace_spans" => (scheduled_for - 60.days).utc.iso8601(6),
      "error_events" => (scheduled_for - 90.days).utc.iso8601(6)
    )
  end

  it "deduplicates the same schedule and reuses a different active run" do
    project = create(:project)
    first = described_class.create_or_find!(
      project: project,
      scheduled_for: scheduled_for,
      dry_run: false,
      trigger_kind: "scheduled"
    )
    duplicate = described_class.create_or_find!(
      project: project,
      scheduled_for: scheduled_for,
      dry_run: false,
      trigger_kind: "scheduled"
    )
    later = described_class.create_or_find!(
      project: project,
      scheduled_for: scheduled_for + 1.day,
      dry_run: false,
      trigger_kind: "scheduled"
    )

    expect(first.created).to be(true)
    expect(duplicate).to have_attributes(run: first.run, created: false)
    expect(later).to have_attributes(run: first.run, created: false)
  end
end
