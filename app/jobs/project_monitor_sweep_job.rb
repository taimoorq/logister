class ProjectMonitorSweepJob < ApplicationJob
  queue_as :notifications

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)
    bucket = now.utc.strftime("%Y%m%d%H")

    CheckInMonitor.includes(:project).find_each do |monitor|
      next if monitor.project.archived?
      next unless monitor.status(at: now) == "missed"

      ProjectMonitorNotificationJob.perform_later(
        monitor.id,
        "monitor_missed",
        {
          "detected_at" => now.utc.iso8601,
          "bucket" => bucket
        }
      )
    end
  end
end
