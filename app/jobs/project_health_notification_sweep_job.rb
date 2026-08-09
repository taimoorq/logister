class ProjectHealthNotificationSweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :notifications
  sidekiq_recurring_schedule(
    key: "project_health_notification_sweep",
    every: 15.minutes,
    arguments: ->(run_at) { [ run_at.utc.iso8601 ] }
  )

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)
    bucket = now.utc.strftime("%Y%m%d%H%M")

    Project.active.find_each do |project|
      dispatch_project_spike(project, now: now, bucket: bucket)
      dispatch_performance_threshold(project, now: now, bucket: bucket)
      dispatch_mobile_health(project, now: now)
    end
  ensure
    reschedule_sidekiq_recurring_job
  end

  private

  def dispatch_project_spike(project, now:, bucket:)
    return unless project.project_notification_preferences.where(project_spike_enabled: true).exists?

    ProjectEmailNotificationDispatcher.call(
      project: project,
      kind: "project_spike",
      metadata: {
        "detected_at" => now.utc.iso8601,
        "bucket" => bucket
      },
      bucket: bucket,
      now: now
    )
  end

  def dispatch_performance_threshold(project, now:, bucket:)
    return unless project.project_notification_preferences.where(performance_alerts_enabled: true).exists?

    ProjectEmailNotificationDispatcher.call(
      project: project,
      kind: "performance_threshold",
      metadata: {
        "detected_at" => now.utc.iso8601,
        "window_minutes" => 15,
        "bucket" => bucket
      },
      bucket: bucket,
      now: now
    )
  end

  def dispatch_mobile_health(project, now:)
    return unless project.integration_android? || project.integration_ios?
    return unless project.project_notification_preferences.where(mobile_health_notifications_enabled: true).exists?

    daily_bucket = now.utc.strftime("%Y%m%d")
    ProjectMobileHealthSignals.new(project, now: now).call.each do |signal|
      ProjectEmailNotificationDispatcher.call(
        project: project,
        kind: signal.kind,
        metadata: signal.metadata,
        subject_key: signal.subject_key,
        bucket: daily_bucket,
        now: now
      )
    end
  end
end
