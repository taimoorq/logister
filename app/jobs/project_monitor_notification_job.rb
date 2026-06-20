class ProjectMonitorNotificationJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(check_in_monitor_id, kind, metadata = {})
    monitor = CheckInMonitor.includes(:project).find(check_in_monitor_id)
    metadata = metadata.stringify_keys

    ProjectEmailNotificationDispatcher.call(
      project: monitor.project,
      kind: kind,
      monitor: monitor,
      metadata: metadata.merge(
        "monitor_id" => monitor.id,
        "monitor_slug" => monitor.slug,
        "environment" => monitor.environment,
        "status" => monitor.status
      ),
      subject_key: monitor.id,
      bucket: bucket_for(kind, metadata)
    )
  end

  private

  def bucket_for(kind, metadata)
    return metadata["bucket"] || metadata[:bucket] if kind.to_s == "monitor_missed"

    nil
  end
end
