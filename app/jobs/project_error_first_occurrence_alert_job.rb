class ProjectErrorFirstOccurrenceAlertJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(error_group_id)
    group = ErrorGroup.includes(:project).find(error_group_id)
    return if group.project.archived?

    group.project.notification_recipients.find_each do |user|
      next if user.respond_to?(:confirmed?) && !user.confirmed?

      preference = ProjectNotificationPreference.for(user: user, project: group.project)
      next unless preference.first_occurrence_enabled?

      delivery = EmailNotificationDelivery.find_or_create_by!(
        dedup_key: EmailNotificationDelivery.first_occurrence_key(user: user, error_group: group)
      ) do |record|
        record.user = user
        record.project = group.project
        record.error_group = group
        record.notification_kind = "first_occurrence"
        record.status = "pending"
      end

      deliver_first_occurrence(delivery)
    end
  end

  private

  def deliver_first_occurrence(delivery)
    delivery.with_lock do
      return if delivery.sent? || delivery.sending_recent?

      delivery.mark_sending!
    end

    ProjectErrorMailer.first_occurrence(delivery).deliver_now
    delivery.mark_sent!
  rescue StandardError => e
    delivery.mark_failed!(e) if delivery&.persisted?
    raise
  end
end
