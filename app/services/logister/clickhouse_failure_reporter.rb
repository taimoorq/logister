require "digest"

module Logister
  class ClickhouseFailureReporter
    DEFAULT_THROTTLE_SECONDS = 60
    EVENT_FAILURE_OPTIONS = {
      kind: "event",
      subject_key: :ingest_event_id,
      log_message: "ClickHouse ingest failed",
      log_fingerprint: "logister:clickhouse_ingest:failure",
      metric_name: "logister.clickhouse.ingest_failure",
      metric_fingerprint: "logister:metric:clickhouse_ingest_failure"
    }.freeze
    SPAN_FAILURE_OPTIONS = {
      kind: "span",
      subject_key: :trace_span_id,
      log_message: "ClickHouse span ingest failed",
      log_fingerprint: "logister:clickhouse_span_ingest:failure",
      metric_name: "logister.clickhouse.span_ingest_failure",
      metric_fingerprint: "logister:metric:clickhouse_span_ingest_failure"
    }.freeze

    class << self
      def report_event_failure(ingest_event_id, error)
        new(**EVENT_FAILURE_OPTIONS, subject_id: ingest_event_id, error: error).call
      end

      def report_span_failure(trace_span_id, error)
        new(**SPAN_FAILURE_OPTIONS, subject_id: trace_span_id, error: error).call
      end
    end

    def initialize(kind:, subject_key:, subject_id:, error:, log_message:, log_fingerprint:, metric_name:, metric_fingerprint:)
      @kind = kind.to_s
      @subject_key = subject_key.to_sym
      @subject_id = subject_id
      @error = error
      @log_message = log_message
      @log_fingerprint = log_fingerprint
      @metric_name = metric_name
      @metric_fingerprint = metric_fingerprint
    end

    def call
      return false unless reportable?

      Logister.report_log(
        message: @log_message,
        level: "error",
        fingerprint: @log_fingerprint,
        context: context
      )
      Logister.report_metric(
        message: @metric_name,
        level: "error",
        fingerprint: @metric_fingerprint,
        context: context.merge(
          metric: {
            name: @metric_name,
            value: 1,
            unit: "count"
          },
          value: 1,
          unit: "count"
        )
      )
      true
    rescue StandardError => report_error
      Rails.logger.warn("clickhouse #{@kind} monitoring failed: #{report_error.class} #{report_error.message}")
      false
    end

    private

    def reportable?
      Rails.cache.write(throttle_cache_key, true, expires_in: throttle_window, unless_exist: true)
    rescue StandardError => cache_error
      Rails.logger.warn("clickhouse #{@kind} throttle failed: #{cache_error.class} #{cache_error.message}")
      true
    end

    def context
      {
        clickhouse_ingest: {
          @subject_key => @subject_id,
          error: {
            class: @error.class.name,
            message: @error.message
          }
        },
        throttle: {
          window_seconds: throttle_window.to_i,
          signature: signature
        }
      }
    end

    def throttle_cache_key
      [ "clickhouse", "failure_report", @kind, signature ]
    end

    def signature
      @signature ||= Digest::SHA256.hexdigest([ @kind, @error.class.name, @error.message ].join("|"))[0, 24]
    end

    def throttle_window
      seconds = Integer(ENV.fetch("LOGISTER_CLICKHOUSE_FAILURE_THROTTLE_SECONDS", DEFAULT_THROTTLE_SECONDS), exception: false)
      [ seconds || DEFAULT_THROTTLE_SECONDS, 1 ].max.seconds
    end
  end
end
