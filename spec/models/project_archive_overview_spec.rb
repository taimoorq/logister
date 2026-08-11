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

  it "never labels a stale active run healthy" do
    now = Time.zone.parse("2026-08-11 12:00:00")
    project = create(:project, user: users(:one))
    policy = create(:project_retention_policy, project: project, archive_enabled: true, archive_before_delete: true)
    run = create(
      :project_retention_run,
      project: project,
      status: "running",
      phase: "uploading",
      heartbeat_at: now - ProjectRetentionRun.stale_after - 1.second,
      objects_total: 50,
      objects_completed: 25
    )

    overview = described_class.new(project: project, policy: policy, now: now)

    expect(overview.health_status).to eq(:archive_run_stale)
    expect(overview.health_tone).to eq(:danger)
    expect(overview.current_retention_run).to eq(run)
    expect(overview.health_message).to include("fenced and resumed")
  end

  it "shows retry state and its retained error instead of reporting healthy" do
    project = create(:project, user: users(:one))
    policy = create(:project_retention_policy, project: project, archive_enabled: true, archive_before_delete: true)
    create(
      :project_retention_run,
      project: project,
      status: "retrying",
      heartbeat_at: Time.current,
      last_error_class: "Timeout::Error",
      last_error_message: "archive storage timed out"
    )

    overview = described_class.new(project: project, policy: policy)

    expect(overview.health_status).to eq(:archive_run_retrying)
    expect(overview.health_message).to include("waiting to retry")
  end

  it "reports verified manifests with unfinished source cleanup" do
    project = create(:project, user: users(:one))
    policy = create(:project_retention_policy, project: project, archive_enabled: true, archive_before_delete: true)
    create(:telemetry_archive, :verified_manifest, project: project, source_deleted_at: nil)

    overview = described_class.new(project: project, policy: policy)

    expect(overview.health_status).to eq(:awaiting_cleanup)
    expect(overview.health_message).to include("1 verified archive still requires source cleanup")
  end

  it "surfaces the latest durable run failure" do
    project = create(:project, user: users(:one))
    policy = create(:project_retention_policy, project: project, archive_enabled: true, archive_before_delete: true)
    create(
      :project_retention_run,
      project: project,
      status: "failed",
      failed_at: Time.current,
      last_error_message: "manifest checksum mismatch"
    )

    overview = described_class.new(project: project, policy: policy)

    expect(overview.health_status).to eq(:needs_attention)
    expect(overview.health_message).to include("manifest checksum mismatch")
  end
end
