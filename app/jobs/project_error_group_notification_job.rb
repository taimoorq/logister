class ProjectErrorGroupNotificationJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(error_group_id, kind, metadata = {})
    group = ErrorGroup.includes(:project).find(error_group_id)
    kind = kind.to_s

    ProjectEmailNotificationDispatcher.call(
      project: group.project,
      kind: kind,
      error_group: group,
      metadata: metadata,
      subject_key: subject_key(group, kind, metadata),
      bucket: bucket_for(kind, metadata)
    )
  end

  private

  def subject_key(group, kind, metadata)
    case kind
    when "regression"
      "#{group.id}:#{group.reopen_count}"
    when "error_milestone"
      "#{group.id}:#{metadata["milestone"] || metadata[:milestone]}"
    else
      group.id
    end
  end

  def bucket_for(kind, metadata)
    return unless kind == "frequent_error"

    metadata["bucket"] || metadata[:bucket]
  end
end
