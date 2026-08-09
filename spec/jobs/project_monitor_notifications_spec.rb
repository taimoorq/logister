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

    missed_intent = NotificationIntent.find_by!(check_in_monitor: monitor, kind: "monitor_missed")
    NotificationIntentDrainJob.perform_now(missed_intent.id)
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

    recovered_intent = NotificationIntent.find_by!(check_in_monitor: monitor, kind: "monitor_recovered")
    NotificationIntentDrainJob.perform_now(recovered_intent.id)
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

    intent = NotificationIntent.find_by!(check_in_monitor: monitor, kind: "monitor_missed")
    NotificationIntentDrainJob.perform_now(intent.id, now.iso8601)
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
    transition_id = SecureRandom.uuid
    monitor = create(
      :check_in_monitor,
      monitoring_paused_at: Time.current,
      notification_state: "paused",
      notification_transition_id: transition_id
    )
    allow(ProjectEmailNotificationDispatcher).to receive(:call)

    ProjectMonitorNotificationJob.perform_now(
      monitor.id,
      "monitor_missed",
      { "transition_id" => transition_id, "expected_status" => "error" }
    )

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

  it "validates the queued cycle identity and current state under the monitor lock" do
    now = Time.current.change(usec: 0)
    project = create(:project)
    api_key = create(:api_key, project: project, user: project.user)
    error_event = check_in_event(project, api_key, status: "error", occurred_at: now, slug: "causality-job")
    monitor = CheckInMonitor.record!(project: project, event: error_event)
    error_intent = NotificationIntent.find_by!(check_in_monitor: monitor, kind: "monitor_missed")
    later_error = check_in_event(project, api_key, status: "error", occurred_at: now + 1.second, slug: "causality-job")
    CheckInMonitor.record!(project: project, event: later_error)
    allow(ProjectEmailNotificationDispatcher).to receive(:call)

    ProjectMonitorNotificationJob.perform_now(monitor.id, "monitor_missed", error_intent.metadata)

    expect(ProjectEmailNotificationDispatcher).to have_received(:call).once

    recovery = check_in_event(project, api_key, status: "ok", occurred_at: now + 2.seconds, slug: "causality-job")
    CheckInMonitor.record!(project: project, event: recovery)
    ProjectMonitorNotificationJob.perform_now(monitor.id, "monitor_missed", error_intent.metadata)

    expect(ProjectEmailNotificationDispatcher).to have_received(:call).once
  end

  it "assigns a distinct deduplication identity to every recovery cycle" do
    now = Time.current.change(usec: 0)
    project = create(:project)
    api_key = create(:api_key, project: project, user: project.user)
    subject_keys = []
    allow(ProjectEmailNotificationDispatcher).to receive(:call) do |**arguments|
      subject_keys << arguments.fetch(:subject_key)
      []
    end

    CheckInMonitor.record!(project: project, event: check_in_event(project, api_key, status: "error", occurred_at: now, slug: "cycle-job"))
    monitor = CheckInMonitor.record!(project: project, event: check_in_event(project, api_key, status: "ok", occurred_at: now + 1.second, slug: "cycle-job"))
    first_recovery = NotificationIntent.where(check_in_monitor: monitor, kind: "monitor_recovered").sole
    ProjectMonitorNotificationJob.perform_now(monitor.id, "monitor_recovered", first_recovery.metadata)
    CheckInMonitor.record!(project: project, event: check_in_event(project, api_key, status: "error", occurred_at: now + 2.seconds, slug: "cycle-job"))
    CheckInMonitor.record!(project: project, event: check_in_event(project, api_key, status: "ok", occurred_at: now + 3.seconds, slug: "cycle-job"))

    recoveries = NotificationIntent.where(check_in_monitor: monitor, kind: "monitor_recovered").order(:id)
    ProjectMonitorNotificationJob.perform_now(monitor.id, "monitor_recovered", recoveries.last.metadata)

    expect(recoveries.size).to eq(2)
    expect(recoveries.map(&:dedup_key).uniq.size).to eq(2)
    expect(recoveries.map { |intent| intent.metadata.fetch("transition_id") }.uniq.size).to eq(2)
    expect(subject_keys.uniq.size).to eq(2)
  end

  def check_in_event(project, api_key, status:, occurred_at:, slug:)
    create(
      :ingest_event,
      :check_in,
      project: project,
      api_key: api_key,
      message: slug,
      occurred_at: occurred_at,
      context: {
        "check_in_slug" => slug,
        "check_in_status" => status,
        "expected_interval_seconds" => 300,
        "environment" => "production"
      }
    )
  end
end
