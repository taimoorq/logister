# frozen_string_literal: true

module Logister
  class ClickhouseRecentCoverageSealer
    DEFAULT_LOOKBACK = 2.hours
    SIGNALS = (ClickhouseCoverage::EVENT_SIGNALS + [ "span" ]).freeze

    def self.call(...)
      new(...).call
    end

    def initialize(project_id:, client:, closed_before: Time.current.beginning_of_hour,
                   lookback: DEFAULT_LOOKBACK,
                   watermark_reconciler: ClickhouseBackfillWatermarkReconciler)
      @project_id = Integer(project_id)
      @client = client
      @closed_before = closed_before.to_time.utc.beginning_of_hour
      @lookback = [ lookback.to_i, 1.hour.to_i ].max.seconds
      @watermark_reconciler = watermark_reconciler
    end

    def call
      return [] unless @client.enabled?

      bucket_starts.flat_map do |bucket_start_at|
        SIGNALS.map do |signal|
          @watermark_reconciler.call(
            client: @client,
            project_id: @project_id,
            signal: signal,
            bucket_start_at: bucket_start_at,
            source_complete: true
          )
        end
      end
    end

    private

    def bucket_starts
      started_at = @closed_before - @lookback
      buckets = []
      cursor = started_at
      while cursor < @closed_before
        buckets << cursor
        cursor += 1.hour
      end
      buckets
    end
  end
end
