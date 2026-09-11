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
      return admission.wake if bounded_admission?
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

    def ensure_scheduled!(now = Time.current, occurrences: sidekiq_recurring_lookahead)
      return admission.recover if bounded_admission?

      super
    end

    def admission
      Logister::TelemetryProjectorAdmission.new
    end

    def bounded_admission?
      Logister::TelemetryProjectorAdmission.enabled? && queue_adapter_name == "sidekiq"
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
    if self.class.bounded_admission?
      session = self.class.admission.enter(job_id)
      return unless session

      run = Logister::TelemetryProjectionRun.new(session: session, seconds: MAX_RUNTIME)
    end
    work_left = false
    failed = false
    clickhouse_client = Logister::ClickhouseClient.new
    metrics = Logister::TelemetryPipelineMetrics.new(operation: "drain")
    projector = Logister::TelemetryProjector.new(clickhouse_client: clickhouse_client, metrics: metrics)
    metrics.capture do
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      max_batches.to_i.clamp(1, MAX_BATCHES_PER_RUN).times do
        break if run && !run.continue?

        result = run ? run.with_database_limits { projector.call(run: run) } : projector.call
        work_left = result.work?
        metrics.count(:batches)
        %i[claimed completed retried terminal_failed].each { |name| metrics.count(name, result.public_send(name)) }
        metrics.count(:empty_batches) unless result.work?
        failed = run && result.retried.positive?
        break if failed
        break unless result.work?
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at >= MAX_RUNTIME
      end
    end
  rescue StandardError => error
    raise unless session

    failed = true
    # PG leases and periodic recovery own retries in bounded mode. Retrying the
    # disposable Sidekiq hint as well would accumulate jobs during an outage.
    Logister::TelemetryProjectorAdmission.warn_failure(error)
  ensure
    close_clickhouse_client(clickhouse_client)
    session&.finish(work_left: work_left, failed: failed)
    reschedule_sidekiq_recurring_job
  end

  private

  def close_clickhouse_client(client)
    client&.close
  rescue StandardError => error
    Rails.logger.warn("telemetry_projector_client_close_error error=#{error.class}: #{error.message}")
  end
end
