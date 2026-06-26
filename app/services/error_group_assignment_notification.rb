# frozen_string_literal: true

class ErrorGroupAssignmentNotification
  def self.call(group, actor:)
    ProjectWorkflowNotificationJob.perform_later(
      group.id,
      "assignment",
      {
        "assigned_user_id" => group.assigned_user_id,
        "actor_user_id" => actor&.id,
        "actor_name" => actor&.name.presence || actor&.email,
        "assigned_at" => group.assigned_at&.utc&.iso8601
      }.compact
    )
  end
end
