# frozen_string_literal: true

class IngestEventsPartitionMaintenanceJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :maintenance
  sidekiq_recurring_schedule(
    key: "ingest_events_partition_maintenance",
    daily_at: "00:20",
    schedule_ttl: 26.hours
  )

  def perform
    result = Logister::IngestEventsPartitioning.new.ensure_future_partitions
    if result.fetch(:blocked_partitions).any?
      Rails.logger.warn(
        "ingest event partition maintenance blocked by default rows: #{result.fetch(:blocked_partitions).to_json}"
      )
    end
  ensure
    reschedule_sidekiq_recurring_job
  end
end
