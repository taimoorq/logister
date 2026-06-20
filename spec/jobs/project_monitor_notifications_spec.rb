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
end
