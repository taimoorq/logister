class ProjectRetentionSweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :default
  sidekiq_recurring_schedule(
    key: "project_telemetry_retention",
    daily_at: "02:00",
    schedule_ttl: 26.hours
  )

  def perform(dry_run: false)
    Project.find_each do |project|
      ProjectRetentionJob.perform_later(project.id, dry_run: dry_run)
    end
  ensure
    reschedule_sidekiq_recurring_job
  end
end
