class ProjectErrorDigestJob < ApplicationJob
  queue_as :notifications

  discard_on ActiveRecord::RecordNotFound

  def perform(preference_id, period_start_at, period_end_at, frequency)
    preference = ProjectNotificationPreference.includes(:project, :user).find(preference_id)
    return unless preference.digest_frequency == frequency

    period_start = Time.zone.parse(period_start_at.to_s)
    period_end = Time.zone.parse(period_end_at.to_s)
    summary = ErrorDigestSummary.new(project: preference.project, period_start: period_start, period_end: period_end)

    delivery = EmailNotificationDelivery.find_or_create_by!(
      dedup_key: EmailNotificationDelivery.digest_key(
        preference: preference,
        period_start: period_start,
        frequency: frequency
      )
    ) do |record|
      record.user = preference.user
      record.project = preference.project
      record.notification_kind = "#{frequency}_digest"
      record.period_start_at = period_start
      record.period_end_at = period_end
      record.status = "pending"
      record.metadata = summary.metadata.merge("digest_frequency" => frequency)
    end

    if summary.empty? && !preference.send_empty_digest?
      delivery.mark_skipped!("No error occurrences in digest period") unless delivery.sent?
      return
    end

    deliver_digest(delivery)
  end

  private

  def deliver_digest(delivery)
    delivery.with_lock do
      return if delivery.sent? || delivery.sending_recent?

      delivery.mark_sending!
    end

    ProjectErrorMailer.digest(delivery).deliver_now
    delivery.mark_sent!
  rescue StandardError => e
    delivery.mark_failed!(e) if delivery&.persisted?
    raise
  end
end
