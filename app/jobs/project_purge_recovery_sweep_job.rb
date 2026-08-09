# frozen_string_literal: true

class ProjectPurgeRecoverySweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :maintenance
  sidekiq_recurring_schedule(
    key: "project_purge_recovery_sweep",
    every: 1.minute,
    arguments: ->(run_at) { [ run_at.utc.iso8601 ] }
  )

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)
    ProjectPurge.active.includes(:steps).find_each do |purge|
      next unless recovery_due?(purge, now)

      ProjectPurgeJob.perform_later(purge.id)
    end
  ensure
    reschedule_sidekiq_recurring_job
  end

  private

  def recovery_due?(purge, now)
    return true if purge.status.in?(%w[requested tombstoned verifying])
    return purge.updated_at <= now - 10.minutes if purge.status == "running"
    return false unless purge.status == "awaiting_external"

    step = purge.steps.find { |candidate| candidate.store_name == purge.current_step }
    retry_at = Time.zone.parse(step&.result&.fetch("retry_at", "").to_s)
    retry_at.present? && retry_at <= now
  end
end
