class ProjectMonitorSweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :notifications
  sidekiq_recurring_schedule(
    key: "project_monitor_sweep",
    every: 15.minutes,
    arguments: ->(run_at) { [ run_at.utc.iso8601 ] }
  )

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)

    CheckInMonitor.monitoring.includes(:project).find_each do |monitor|
      CheckInMonitor.capture_missed_notification!(monitor: monitor, detected_at: now)
    end
  ensure
    reschedule_sidekiq_recurring_job
  end
end
