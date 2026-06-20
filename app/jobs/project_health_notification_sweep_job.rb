class ProjectHealthNotificationSweepJob < ApplicationJob
  queue_as :notifications

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)
    bucket = now.utc.strftime("%Y%m%d%H%M")

    Project.active.find_each do |project|
      dispatch_project_spike(project, now: now, bucket: bucket)
      dispatch_performance_threshold(project, now: now, bucket: bucket)
    end
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
end
