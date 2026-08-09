# frozen_string_literal: true

class TelemetryLedgerCleanupJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :maintenance
  sidekiq_recurring_schedule(
    key: "telemetry_ledger_cleanup",
    daily_at: "03:30",
    schedule_ttl: 26.hours
  )

  def perform(expired_before = Time.current.iso8601)
    Logister::TelemetryLedgerCleanup.call(expired_before: Time.zone.parse(expired_before.to_s))
  ensure
    reschedule_sidekiq_recurring_job
  end
end
