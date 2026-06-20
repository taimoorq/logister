class ProjectUsageNotificationJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(project_id, metadata = {})
    project = Project.find(project_id)
    metadata = metadata.stringify_keys

    ProjectEmailNotificationDispatcher.call(
      project: project,
      kind: "usage_alert",
      metadata: metadata,
      subject_key: metadata["reason"].presence || "usage",
      bucket: Time.current.utc.strftime("%Y%m%d%H")
    )
  end
end
