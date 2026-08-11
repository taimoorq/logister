class ProjectRetentionSweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :maintenance
  sidekiq_recurring_schedule(
    key: "project_telemetry_retention",
    daily_at: "02:00",
    schedule_ttl: 26.hours
  )

  def perform(dry_run: false)
    scheduled_for = Time.current.change(usec: 0)
    Project.find_each do |project|
      outcome = Logister::ProjectRetentionRunCoordinator.create_or_find!(
        project: project,
        scheduled_for: scheduled_for,
        dry_run: dry_run,
        trigger_kind: "scheduled"
      )
      next unless outcome.created

      ProjectRetentionJob.perform_later(project.id, dry_run: dry_run, run_id: outcome.run.id)
    end
  ensure
    reschedule_sidekiq_recurring_job
  end
end
