# frozen_string_literal: true

class ProjectRetentionRunRecoverySweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :maintenance
  sidekiq_recurring_schedule(
    key: "project_retention_run_recovery_sweep",
    every: 1.minute,
    arguments: ->(run_at) { [ run_at.utc.iso8601(6) ] }
  )

  def perform(now_iso8601 = Time.current.iso8601(6))
    now = Time.zone.parse(now_iso8601.to_s)
    recover_stale_running!(now)
    enqueue_due_runs!(now)
  ensure
    reschedule_sidekiq_recurring_job
  end

  private

  def recover_stale_running!(now)
    ProjectRetentionRun.where(status: "running").stale_before(now - stale_after).find_each do |run|
      recovered = run.with_lock do
        run.reload
        next unless run.status == "running" && run.stale?(before: now - stale_after)

        metadata = run.metadata.to_h.merge(
          "last_recovery" => {
            "reason" => "stale_heartbeat",
            "at" => now.utc.iso8601(6),
            "fenced_attempt_token" => run.attempt_token
          }
        )
        run.update!(
          status: "retrying",
          fence_version: run.fence_version.to_i + 1,
          attempt_token: nil,
          available_at: now,
          recovery_enqueued_at: nil,
          metadata: metadata
        )
        true
      end
      if recovered
        Logister::ProjectRetentionRunTelemetry.emit(
          event: "stale_attempt_recovered",
          run: run,
          at: now,
          action: "retry",
          reason: "stale_heartbeat"
        )
      end
    end
  end

  def enqueue_due_runs!(now)
    ProjectRetentionRun
      .where(status: %w[queued retrying waiting])
      .where("available_at IS NULL OR available_at <= ?", now)
      .where("recovery_enqueued_at IS NULL OR recovery_enqueued_at < ?", now - enqueue_claim_ttl)
      .find_each do |run|
        claimed = run.with_lock do
          run.reload
          next false unless run.status.in?(%w[queued retrying waiting])
          next false if run.available_at.present? && run.available_at > now
          next false if run.recovery_enqueued_at.present? && run.recovery_enqueued_at >= now - enqueue_claim_ttl

          run.update!(recovery_enqueued_at: now)
          true
        end
        next unless claimed

        ProjectRetentionJob.perform_later(
          run.project_id,
          dry_run: run.dry_run?,
          run_id: run.id
        )
        Logister::ProjectRetentionRunTelemetry.emit(
          event: "recovery_enqueued",
          run: run,
          at: now,
          action: "enqueue"
        )
      end
  end

  def stale_after
    ProjectRetentionRun.stale_after
  end

  def enqueue_claim_ttl
    seconds_env("LOGISTER_RETENTION_ENQUEUE_CLAIM_SECONDS", 5.minutes.to_i)
  end

  def seconds_env(name, fallback)
    value = Integer(ENV.fetch(name, fallback))
    (value.positive? ? value : fallback).seconds
  rescue ArgumentError, TypeError
    fallback.seconds
  end
end
