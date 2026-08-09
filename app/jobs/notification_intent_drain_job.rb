class NotificationIntentDrainJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound
  retry_on StandardError, wait: :polynomially_longer, attempts: 8

  def perform(intent_id, now_iso8601 = nil)
    intent = NotificationIntent.find(intent_id)
    now = now_iso8601.present? ? Time.zone.parse(now_iso8601.to_s) : Time.current
    token = intent.claim!(now: now)
    return unless token

    enqueue_notification!(intent)
    intent.mark_enqueued!(token, now: now)
  rescue StandardError => error
    intent&.release!(token, error, now: now || Time.current) if token.present?
    raise
  end

  private

  def enqueue_notification!(intent)
    metadata = intent.metadata.deep_dup
    job =
      case intent.kind
      when "first_occurrence"
        ProjectErrorFirstOccurrenceAlertJob.perform_later(intent.error_group_id)
      when "regression", "error_milestone"
        ProjectErrorGroupNotificationJob.perform_later(intent.error_group_id, intent.kind, metadata)
      when "monitor_missed", "monitor_recovered"
        ProjectMonitorNotificationJob.perform_later(intent.check_in_monitor_id, intent.kind, metadata)
      end

    return if job && (!job.respond_to?(:successfully_enqueued?) || job.successfully_enqueued?)

    raise ActiveJob::EnqueueError, "notification target for intent #{intent.id} was not enqueued"
  end
end
