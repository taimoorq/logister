# frozen_string_literal: true

module Logister
  # One sampled summary per intake or drain; never retain SQL or event payloads.
  class TelemetryPipelineMetrics
    def initialize(operation:, sampled: nil)
      @operation = operation
      @sampled = sampled.nil? ? sample? : sampled
      @phases = Hash.new { |hash, key| hash[key] = { duration_ms: 0.0, queries: 0, sql_ms: 0.0 } }
      @counts = Hash.new(0)
      @phase = :other
    end

    def capture
      return yield unless @sampled

      started = monotonic
      owner_thread = Thread.current
      owner_fiber = Fiber.current
      subscriber = ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") do |_name, start, finish, _id, payload|
        next unless Thread.current == owner_thread && Fiber.current == owner_fiber
        next if payload[:cached] || payload[:name].in?(%w[SCHEMA TRANSACTION])

        @phases[@phase][:queries] += 1
        @phases[@phase][:sql_ms] += (finish - start) * 1_000
      end
      yield
    rescue StandardError => error
      error_class = error.class.name
      raise
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      emit(started, error_class) if started
    end

    def measure(phase)
      return yield unless @sampled

      previous = @phase
      @phase = phase
      started = monotonic
      yield
    ensure
      if started
        @phases[phase][:duration_ms] += (monotonic - started) * 1_000
        @phase = previous
      end
    end

    def count(name, value = 1)
      @counts[name] += value if @sampled
    end

    private

    def sample?
      rate = Float(ENV.fetch("LOGISTER_TELEMETRY_PROFILE_SAMPLE_RATE", "0.01"), exception: false)
      Rails.env.production? && rate&.finite? && rand < rate.clamp(0, 1)
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def emit(started, error_class)
      summary = {
        operation: @operation,
        duration_ms: ((monotonic - started) * 1_000).round(2),
        error_class: error_class,
        counts: @counts,
        phases: @phases.transform_values { |values| values.transform_values { |value| value.round(2) } }
      }
      SelfReportingGuard.suppress { Rails.logger.info("telemetry_pipeline #{summary.to_json}") }
    rescue StandardError
      # Observability must never change acceptance or acknowledgement outcomes.
      nil
    end
  end
end
