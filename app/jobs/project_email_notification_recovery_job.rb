class ProjectEmailNotificationRecoveryJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(delivery_id, now_iso8601 = Time.current.iso8601)
    delivery = EmailNotificationDelivery.includes(:project, :user, :error_group).find(delivery_id)
    now = Time.zone.parse(now_iso8601.to_s)
    return unless delivery.sending_stale?(now: now)

    ProjectEmailNotificationDispatcher.resume(delivery, now: now)
  end
end
