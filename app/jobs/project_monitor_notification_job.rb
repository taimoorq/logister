class ProjectMonitorNotificationJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(check_in_monitor_id, kind, metadata = {})
    monitor = CheckInMonitor.includes(:project).find(check_in_monitor_id)
    kind = kind.to_s
    metadata = metadata.stringify_keys
    snapshot = current_transition_snapshot(monitor, kind, metadata)
    return unless snapshot

    ProjectEmailNotificationDispatcher.call(
      project: snapshot.fetch(:project),
      kind: kind,
      monitor: monitor,
      metadata: metadata.merge(
        "monitor_id" => monitor.id,
        "monitor_slug" => monitor.slug,
        "environment" => monitor.environment,
        "status" => snapshot.fetch(:status)
      ),
      subject_key: "#{monitor.id}:transition:#{metadata.fetch('transition_id')}",
      bucket: bucket_for(kind, metadata)
    )
  end

  private

  def current_transition_snapshot(monitor, kind, metadata)
    transition_id = metadata["transition_id"].presence
    expected_status = metadata["expected_status"].presence
    return if transition_id.blank? || !expected_status_for_kind?(kind, expected_status)

    monitor.with_lock do
      project = monitor.project.reload
      next if project.notifications_disabled? || monitor.monitoring_paused?
      next unless monitor.notification_transition_id.to_s == transition_id.to_s

      current_status = monitor.status(at: Time.current)
      next unless current_status == expected_status

      { project: project, status: current_status }
    end
  end

  def expected_status_for_kind?(kind, status)
    return status.in?(%w[error missed]) if kind == "monitor_missed"
    return status == "ok" if kind == "monitor_recovered"

    false
  end

  def bucket_for(kind, metadata)
    return metadata["bucket"] if kind == "monitor_missed"

    nil
  end
end
