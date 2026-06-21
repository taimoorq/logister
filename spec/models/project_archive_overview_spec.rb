# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectArchiveOverview, type: :model do
  it "reports not archiving when archive exports are off" do
    project = create(:project, user: users(:one))
    policy = create(
      :project_retention_policy,
      project: project,
      archive_enabled: false,
      archive_before_delete: false
    )

    overview = described_class.new(project: project, policy: policy)

    expect(overview.health_status).to eq(:not_archiving)
    expect(overview.health_label).to eq("Not archiving")
    expect(overview.health_message).to include("Archive retained data is off")
  end

  it "explains when exports are enabled but deletion is not protected" do
    project = create(:project, user: users(:one))
    policy = create(
      :project_retention_policy,
      project: project,
      archive_enabled: true,
      archive_before_delete: false
    )

    overview = described_class.new(project: project, policy: policy)

    expect(overview.health_status).to eq(:archive_not_required)
    expect(overview.health_label).to eq("Archiving enabled, deletion not protected")
    expect(overview.health_message).to include("retention cleanup can still delete rows")
    expect(overview.coverage_rows.find { |row| row.key == :hot_events }.status).to eq(:archive_not_required)
  end

  it "reports protected before deletion when exports and the delete guard are enabled" do
    project = create(:project, user: users(:one))
    policy = create(
      :project_retention_policy,
      project: project,
      archive_enabled: true,
      archive_before_delete: true
    )

    overview = described_class.new(project: project, policy: policy)

    expect(overview.health_status).to eq(:healthy)
    expect(overview.health_label).to eq("Protected before deletion")
    expect(overview.health_message).to include("must write a successful archive")
  end

  it "flags a scope with retention candidates older than the latest completed archive" do
    project = create(:project, user: users(:one))
    last_cleanup_at = Time.zone.parse("2026-06-21 02:00:00")
    policy = create(
      :project_retention_policy,
      project: project,
      archive_enabled: true,
      archive_before_delete: true,
      hot_retention_days: 30,
      trace_retention_days: 30,
      last_retention_run_at: last_cleanup_at,
      last_retention_result: {
        candidates: {
          hot_events: 3,
          trace_spans: 0,
          closed_error_groups: 0
        },
        deleted: {
          hot_events: 0,
          trace_spans: 0,
          closed_error_groups: 0
        }
      }
    )
    create(
      :telemetry_archive,
      project: project,
      scope: "hot_events",
      before_at: last_cleanup_at - 31.days,
      rows: 10,
      created_at: last_cleanup_at
    )

    overview = described_class.new(project: project, policy: policy, now: last_cleanup_at)
    hot_events = overview.coverage_rows.find { |row| row.key == :hot_events }

    expect(hot_events.status).to eq(:archive_gap)
    expect(hot_events.status_label).to eq("Archive gap")
    expect(overview.health_status).to eq(:archive_gap)
  end
end
