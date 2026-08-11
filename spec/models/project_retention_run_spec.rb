# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectRetentionRun, type: :model do
  it "derives a stable run identity from project, schedule, and dry-run mode" do
    project = create(:project)
    scheduled_for = Time.zone.parse("2026-08-11 02:00:00")

    first = build(:project_retention_run, project: project, scheduled_for: scheduled_for)
    second = build(:project_retention_run, project: project, scheduled_for: scheduled_for)
    dry_run = build(:project_retention_run, project: project, scheduled_for: scheduled_for, dry_run: true)

    expect(first).to be_valid
    expect(second).to be_valid
    expect(first.run_key).to eq(second.run_key)
    expect(dry_run.tap(&:valid?).run_key).not_to eq(first.run_key)
  end

  it "enforces one active non-dry-run per project at the database boundary" do
    project = create(:project)
    first = create(:project_retention_run, project: project, scheduled_for: 1.hour.ago)

    expect {
      create(:project_retention_run, project: project, scheduled_for: Time.current)
    }.to raise_error(ActiveRecord::RecordNotUnique)

    first.update!(status: "completed", completed_at: Time.current)
    expect {
      create(:project_retention_run, project: project, scheduled_for: Time.current)
    }.to change(described_class, :count).by(1)
  end

  it "rejects progress beyond the durable totals" do
    run = build(:project_retention_run, objects_total: 1, objects_completed: 2)

    expect(run).not_to be_valid
    expect(run.errors[:objects_completed]).to include("cannot exceed total objects")
  end
end
