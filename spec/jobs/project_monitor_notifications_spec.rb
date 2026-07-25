# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project monitor notifications", type: :job do
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs }

  it "enqueues missed and recovered monitor notifications from check-in events" do
    project = create(:project)
    api_key = create(:api_key, project: project, user: project.user)
    error_event = create(
      :ingest_event,
      :check_in,
      project: project,
      api_key: api_key,
      message: "billing-sync",
      occurred_at: Time.zone.parse("2026-06-20 12:00:00 UTC"),
      context: {
        "check_in_slug" => "billing-sync",
        "check_in_status" => "error",
        "expected_interval_seconds" => 300,
        "environment" => "production"
      }
    )

    monitor = CheckInMonitor.record!(project: project, event: error_event)

    expect(ProjectMonitorNotificationJob).to have_been_enqueued.with(monitor.id, "monitor_missed", hash_including("event_id" => error_event.id))

    ok_event = create(
      :ingest_event,
      :check_in,
      project: project,
      api_key: api_key,
      message: "billing-sync",
      occurred_at: Time.zone.parse("2026-06-20 12:05:00 UTC"),
      context: {
        "check_in_slug" => "billing-sync",
        "check_in_status" => "ok",
        "expected_interval_seconds" => 300,
        "environment" => "production"
      }
    )

    CheckInMonitor.record!(project: project, event: ok_event)

    expect(ProjectMonitorNotificationJob).to have_been_enqueued.with(monitor.id, "monitor_recovered", hash_including("event_id" => ok_event.id))
  end

  it "sweeps missed monitors and queues an hourly bucketed alert" do
    now = Time.zone.parse("2026-06-20 12:10:00 UTC")
    monitor = create(
      :check_in_monitor,
      expected_interval_seconds: 60,
      last_check_in_at: now - 10.minutes,
      last_status: "ok"
    )

    ProjectMonitorSweepJob.perform_now(now.iso8601)

    expect(ProjectMonitorNotificationJob).to have_been_enqueued.with(
      monitor.id,
      "monitor_missed",
      hash_including("bucket" => "2026062012")
    )
  end

  it "does not sweep a missed monitor while monitoring is paused" do
    now = Time.zone.parse("2026-06-20 12:10:00 UTC")
    create(
      :check_in_monitor,
      expected_interval_seconds: 60,
      last_check_in_at: now - 10.minutes,
      last_status: "ok",
      monitoring_paused_at: now - 1.minute
    )

    ProjectMonitorSweepJob.perform_now(now.iso8601)

    expect(ProjectMonitorNotificationJob).not_to have_been_enqueued
  end

  it "discards a queued monitor notification after monitoring is paused" do
    monitor = create(:check_in_monitor, monitoring_paused_at: Time.current)
    allow(ProjectEmailNotificationDispatcher).to receive(:call)

    ProjectMonitorNotificationJob.perform_now(monitor.id, "monitor_missed")

    expect(ProjectEmailNotificationDispatcher).not_to have_received(:call)
  end

  it "keeps monitoring paused when a new check-in arrives" do
    project = create(:project)
    api_key = create(:api_key, project: project, user: project.user)
    monitor = create(
      :check_in_monitor,
      project: project,
      slug: "paused-job",
      monitoring_paused_at: 1.hour.ago
    )
    event = create(
      :ingest_event,
      :check_in,
      project: project,
      api_key: api_key,
      message: monitor.slug,
      context: {
        "check_in_slug" => monitor.slug,
        "check_in_status" => "error",
        "expected_interval_seconds" => 300,
        "environment" => monitor.environment
      }
    )

    CheckInMonitor.record!(project: project, event: event)

    expect(monitor.reload).to be_monitoring_paused
    expect(monitor.status).to eq("paused")
    expect(ProjectMonitorNotificationJob).not_to have_been_enqueued
  end
end
