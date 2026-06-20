class ProjectWorkflowNotificationJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(error_group_id, kind, metadata = {})
    group = ErrorGroup.includes(:project).find(error_group_id)
    metadata = metadata.stringify_keys

    ProjectEmailNotificationDispatcher.call(
      project: group.project,
      kind: kind,
      error_group: group,
      metadata: metadata,
      subject_key: subject_key(group, kind, metadata)
    )
  end

  private

  def subject_key(group, kind, metadata)
    [
      group.id,
      kind,
      metadata["assigned_user_id"],
      metadata["status"],
      metadata["actor_user_id"],
      Time.current.utc.strftime("%Y%m%d%H%M")
    ].compact.join(":")
  end
end
