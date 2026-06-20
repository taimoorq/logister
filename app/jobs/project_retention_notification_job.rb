class ProjectRetentionNotificationJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(project_id, metadata = {})
    project = Project.find(project_id)
    metadata = metadata.stringify_keys

    ProjectEmailNotificationDispatcher.call(
      project: project,
      kind: "retention_failure",
      metadata: metadata,
      subject_key: metadata["scope"].presence || project.id,
      bucket: Time.current.utc.strftime("%Y%m%d%H")
    )
  end
end
