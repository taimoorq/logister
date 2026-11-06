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
    partitioning = Logister::IngestEventsPartitioning.new
    result = partitioning.ensure_future_partitions
    if result.fetch(:blocked_partitions).any?
      Rails.logger.warn(
        "ingest event partition maintenance blocked by default rows: #{result.fetch(:blocked_partitions).to_json}"
      )
    end

    retirement = partitioning.retire_expired_partitions
    if retirement.fetch(:retired_partitions).any?
      Rails.logger.info(
        "ingest event partition maintenance retired expired partitions: #{retirement.fetch(:retired_partitions).to_json}"
      )
    end

    candidates = partitioning.compaction_candidates
    if candidates.any?
      summary = candidates.map { |partition| partition.slice(:name, :total_bytes, :estimated_reclaimable_bytes) }
      Rails.logger.warn("ingest event partitions need operator compaction: #{summary.to_json}")
    end
  ensure
    reschedule_sidekiq_recurring_job
  end
end
