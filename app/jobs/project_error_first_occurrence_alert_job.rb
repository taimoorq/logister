class ProjectErrorFirstOccurrenceAlertJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(error_group_id, metadata = {})
    group = ErrorGroup.includes(:project).find(error_group_id)
    metadata = metadata.to_h.stringify_keys
    ProjectEmailNotificationDispatcher.call(
      project: group.project,
      kind: "first_occurrence",
      error_group: group,
      metadata: metadata.reverse_merge(
        "occurred_at" => group.first_seen_at&.utc&.iso8601
      )
    )
  end
end
