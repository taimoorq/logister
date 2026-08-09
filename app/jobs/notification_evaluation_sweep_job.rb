class NotificationEvaluationSweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :notifications
  sidekiq_recurring_schedule(
    key: "notification_evaluation_sweep",
    every: 5.minutes,
    arguments: ->(run_at) { [ run_at.utc.iso8601 ] }
  )

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)
    NotificationEvaluation.ready(now).limit(500).pluck(:id).each do |evaluation_id|
      FrequentErrorNotificationEvaluationJob.perform_later(evaluation_id, now.utc.iso8601)
    end
  ensure
    reschedule_sidekiq_recurring_job
  end
end
