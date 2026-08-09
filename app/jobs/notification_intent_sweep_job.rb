class NotificationIntentSweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :notifications
  sidekiq_recurring_schedule(
    key: "notification_intent_sweep",
    every: 1.minute,
    arguments: ->(run_at) { [ run_at.utc.iso8601 ] }
  )

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)
    NotificationIntent.ready(now).order(:available_at, :id).limit(500).pluck(:id).each do |intent_id|
      job = NotificationIntentDrainJob.perform_later(intent_id, now.utc.iso8601)
      unless job && (!job.respond_to?(:successfully_enqueued?) || job.successfully_enqueued?)
        raise ActiveJob::EnqueueError, "notification intent #{intent_id} drainer was not enqueued"
      end
    rescue StandardError => error
      Rails.logger.warn(
        "notification_intent.sweep_enqueue_failed intent_id=#{intent_id} " \
        "error=#{error.class}: #{error.message}"
      )
    end
  ensure
    reschedule_sidekiq_recurring_job
  end
end
