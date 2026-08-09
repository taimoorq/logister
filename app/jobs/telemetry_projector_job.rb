# frozen_string_literal: true

class TelemetryProjectorJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :projector
  sidekiq_recurring_schedule(
    key: "telemetry_projector",
    every: 1.minute
  )

  MAX_BATCHES_PER_RUN = 20
  MAX_RUNTIME = 25.seconds
  WAKE_KEY = "logister:telemetry_projector:wake:v1"
  WAKE_TTL = 5.seconds

  class << self
    def wake!
      return enqueue_without_coalescing unless queue_adapter_name == "sidekiq"

      acquired = Sidekiq.redis do |redis|
        redis.set(WAKE_KEY, Time.current.utc.iso8601(6), nx: true, ex: WAKE_TTL.to_i)
      end
      return false unless acquired

      enqueue_without_coalescing
    rescue StandardError => coalescing_error
      Rails.logger.warn(
        "telemetry_projector_wake_coalescing_error " \
        "error=#{coalescing_error.class}: #{coalescing_error.message}"
      )
      enqueue_without_coalescing
    end

    private

    def enqueue_without_coalescing
      perform_later
      true
    rescue StandardError => enqueue_error
      Rails.logger.error(
        "telemetry_projector_wake_enqueue_error " \
        "error=#{enqueue_error.class}: #{enqueue_error.message}"
      )
      false
    end
  end

  def perform(max_batches: MAX_BATCHES_PER_RUN)
    clickhouse_client = Logister::ClickhouseClient.new
    projector = Logister::TelemetryProjector.new(clickhouse_client: clickhouse_client)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    max_batches.to_i.clamp(1, MAX_BATCHES_PER_RUN).times do
      result = projector.call
      break unless result.work?
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at >= MAX_RUNTIME
    end
  ensure
    close_clickhouse_client(clickhouse_client)
    reschedule_sidekiq_recurring_job
  end

  private

  def close_clickhouse_client(client)
    client&.close
  rescue StandardError => error
    Rails.logger.warn("telemetry_projector_client_close_error error=#{error.class}: #{error.message}")
  end
end
