class ProjectEmailNotificationRecoverySweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :notifications
  sidekiq_recurring_schedule(
    key: "project_email_notification_recovery_sweep",
    every: 5.minutes,
    arguments: ->(run_at) { [ run_at.utc.iso8601 ] }
  )

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)
    EmailNotificationDelivery.stale_sending(now).limit(500).pluck(:id).each do |delivery_id|
      ProjectEmailNotificationRecoveryJob.perform_later(delivery_id, now.utc.iso8601)
    end
  ensure
    reschedule_sidekiq_recurring_job
  end
end
