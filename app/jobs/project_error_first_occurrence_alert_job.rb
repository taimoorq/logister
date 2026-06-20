class ProjectErrorFirstOccurrenceAlertJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(error_group_id)
    group = ErrorGroup.includes(:project).find(error_group_id)
    ProjectEmailNotificationDispatcher.call(
      project: group.project,
      kind: "first_occurrence",
      error_group: group,
      metadata: {
        "occurred_at" => group.first_seen_at&.utc&.iso8601
      }
    )
  end
end
