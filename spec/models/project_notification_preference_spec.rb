# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectNotificationPreference, type: :model do
  describe ".for" do
    it "creates default project email preferences" do
      preference = described_class.for(user: users(:one), project: projects(:one))

      expect(preference).to be_persisted
      expect(preference.first_occurrence_enabled).to be true
      expect(preference.digest_frequency).to eq("none")
      expect(preference.digest_send_hour).to eq(9)
      expect(preference.time_zone).to eq("UTC")
      expect(preference.regression_enabled).to be true
      expect(preference.workflow_mode).to eq("assigned_to_me")
      expect(preference.monitor_alerts_enabled).to be true
      expect(preference.retention_notifications_enabled).to be true
    end
  end

  describe ".for_active_projects" do
    it "excludes preferences for archived projects" do
      active_project = create(:project, user: users(:one))
      archived_project = create(:project, :archived, user: users(:one))
      active_preference = create(:project_notification_preference, :daily, project: active_project, user: users(:one))
      archived_preference = create(:project_notification_preference, :daily, project: archived_project, user: users(:one))

      expect(described_class.for_active_projects).to include(active_preference)
      expect(described_class.for_active_projects).not_to include(archived_preference)
    end
  end

  describe "#due_digest_window" do
    it "returns the previous day after the local send hour for daily digests" do
      preference = build(:project_notification_preference, :daily, digest_send_hour: 9, time_zone: "UTC")

      window = preference.due_digest_window(Time.zone.parse("2026-05-09 09:15:00 UTC"))

      expect(window.map(&:utc)).to eq([
        Time.zone.parse("2026-05-08 00:00:00 UTC"),
        Time.zone.parse("2026-05-09 00:00:00 UTC")
      ])
    end

    it "waits until Monday send hour for weekly digests" do
      preference = build(:project_notification_preference, :weekly, digest_send_hour: 9, time_zone: "UTC")

      expect(preference.due_digest_window(Time.zone.parse("2026-05-10 10:00:00 UTC"))).to be_nil
      expect(preference.due_digest_window(Time.zone.parse("2026-05-11 08:59:00 UTC"))).to be_nil

      window = preference.due_digest_window(Time.zone.parse("2026-05-11 09:00:00 UTC"))
      expect(window.map(&:utc)).to eq([
        Time.zone.parse("2026-05-04 00:00:00 UTC"),
        Time.zone.parse("2026-05-11 00:00:00 UTC")
      ])
    end
  end

  it "rejects unknown time zones" do
    preference = build(:project_notification_preference, time_zone: "Mars/Base")

    expect(preference).not_to be_valid
    expect(preference.errors[:time_zone]).to include("is not supported")
  end

  it "matches immediate error alerts against environment, severity, and status filters" do
    project = create(:project)
    group = create(:error_group, project: project, stage: "production", severity: "error", status: :unresolved)
    preference = build(
      :project_notification_preference,
      project: project,
      environment_filter: "production",
      severity_filter: "error",
      status_filter: "unresolved"
    )

    expect(preference.immediate_email_enabled_for?("regression", error_group: group)).to be true

    preference.environment_filter = "staging"
    expect(preference.immediate_email_enabled_for?("regression", error_group: group)).to be false
  end

  it "limits assignment workflow emails to the assigned user by default" do
    project = create(:project)
    assignee = project.user
    other_user = create(:user)
    group = create(:error_group, project: project, assignee: assignee)
    assigned_preference = build(:project_notification_preference, project: project, user: assignee)
    other_preference = build(:project_notification_preference, project: project, user: other_user)

    metadata = { "assigned_user_id" => assignee.id }

    expect(assigned_preference.immediate_email_enabled_for?("assignment", error_group: group, metadata: metadata)).to be true
    expect(other_preference.immediate_email_enabled_for?("assignment", error_group: group, metadata: metadata)).to be false
  end

  it "limits status workflow emails to errors assigned to the user by default" do
    project = create(:project)
    assignee = project.user
    actor = create(:user)
    other_user = create(:user)
    group = create(:error_group, project: project, assignee: assignee)
    assigned_preference = build(:project_notification_preference, project: project, user: assignee)
    other_preference = build(:project_notification_preference, project: project, user: other_user)

    metadata = { "actor_user_id" => actor.id }

    expect(assigned_preference.immediate_email_enabled_for?("status_change", error_group: group, metadata: metadata)).to be true
    expect(other_preference.immediate_email_enabled_for?("status_change", error_group: group, metadata: metadata)).to be false
  end

  it "suppresses immediate email during quiet hours" do
    preference = build(
      :project_notification_preference,
      quiet_hours_enabled: true,
      quiet_hours_start: 22,
      quiet_hours_end: 7,
      time_zone: "UTC"
    )
    quiet_time = Time.zone.parse("2026-05-09 23:00:00 UTC")
    active_time = Time.zone.parse("2026-05-09 12:00:00 UTC")

    expect(preference.quiet_hours_active?(quiet_time)).to be true
    expect(preference.quiet_hours_active?(active_time)).to be false
    expect(preference.immediate_email_enabled_for?("monitor_missed", now: quiet_time)).to be false
  end

  it "turns off every email category when unsubscribing from project email" do
    preference = create(:project_notification_preference, :daily, frequent_error_enabled: true, milestone_alerts_enabled: true)

    preference.unsubscribe_from_project_email!

    expect(preference.reload.first_occurrence_enabled).to be false
    expect(preference.regression_enabled).to be false
    expect(preference.frequent_error_enabled).to be false
    expect(preference.workflow_mode).to eq("off")
    expect(preference.monitor_alerts_enabled).to be false
    expect(preference.retention_notifications_enabled).to be false
    expect(preference.digest_frequency).to eq("none")
  end
end
