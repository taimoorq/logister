# frozen_string_literal: true

module Logister
  class ClickhouseCoverage
    EVENT_SIGNALS = %w[error metric transaction log check_in].freeze
    SIGNAL_DESTINATIONS = EVENT_SIGNALS.index_with { "clickhouse_event" }.merge("span" => "clickhouse_span").freeze

    Result = Data.define(
      :complete,
      :reason,
      :project_ids,
      :signals,
      :started_at,
      :ended_at,
      :required_bucket_count,
      :complete_bucket_count,
      :incomplete_buckets,
      :fresh_through,
      :last_delivered_at
    ) do
      def complete?
        complete
      end

      def coverage_ratio
        return complete? ? 1.0 : 0.0 if required_bucket_count.zero?

        complete_bucket_count.fdiv(required_bucket_count).round(4)
      end

      def to_h
        {
          complete: complete?,
          reason: reason,
          projects: project_ids,
          signals: signals,
          started_at: started_at&.utc&.iso8601,
          ended_at: ended_at&.utc&.iso8601,
          required_bucket_count: required_bucket_count,
          complete_bucket_count: complete_bucket_count,
          coverage_ratio: coverage_ratio,
          incomplete_buckets: incomplete_buckets,
          fresh_through: fresh_through&.utc&.iso8601,
          last_delivered_at: last_delivered_at&.utc&.iso8601
        }
      end
    end

    class Repository
      def watermarks(project_ids:, signals:, started_at:, ended_at:)
        pairs = signals.filter_map do |signal|
          destination = SIGNAL_DESTINATIONS[signal]
          [ signal, destination ] if destination
        end
        return TelemetryProjectionWatermark.none if pairs.empty?

        watermark_table = TelemetryProjectionWatermark.arel_table
        exact_pair = pairs.map do |signal, destination|
          watermark_table[:signal].eq(signal).and(watermark_table[:destination].eq(destination))
        end.reduce(&:or)
        TelemetryProjectionWatermark.where(
          project_id: project_ids,
          bucket_start_at: started_at.utc.beginning_of_hour...ended_at
        ).where(exact_pair).to_a
      end
    end

    class << self
      def call(...)
        new(...).call
      end
    end

    def initialize(project_ids:, signals:, from:, to:, repository: Repository.new)
      @project_ids = Array(project_ids).map(&:to_i).select(&:positive?).uniq.sort
      @signals = Array(signals).map(&:to_s).select { |signal| SIGNAL_DESTINATIONS.key?(signal) }.uniq.sort
      @started_at = from.to_time.utc
      @ended_at = to.to_time.utc
      @repository = repository
    end

    def call
      return result(complete: false, reason: "invalid_range", required: [], complete_keys: [], watermarks: []) if invalid_range?

      watermarks = @repository.watermarks(
        project_ids: @project_ids,
        signals: @signals,
        started_at: @started_at,
        ended_at: @ended_at
      )
      watermark_by_key = watermarks.index_by { |watermark| key_for(watermark) }
      required = required_bucket_keys
      complete_keys = required.select { |key| watermark_by_key[key]&.complete? }
      complete = required.any? && complete_keys.length == required.length
      reason = if required.empty? || watermarks.empty?
        "no_coverage_evidence"
      elsif complete
        "complete"
      else
        "incomplete_watermarks"
      end

      result(complete:, reason:, required:, complete_keys:, watermarks:)
    end

    private

    def invalid_range?
      @project_ids.empty? || @signals.empty? || @ended_at <= @started_at
    end

    def required_bucket_keys
      buckets = []
      cursor = @started_at.beginning_of_hour
      while cursor < @ended_at
        buckets << cursor
        cursor += 1.hour
      end

      @project_ids.product(@signals, buckets).map do |project_id, signal, bucket|
        [ project_id, signal, bucket ]
      end.sort
    end

    def key_for(watermark)
      [ watermark.project_id.to_i, watermark.signal.to_s, watermark.bucket_start_at.utc.beginning_of_hour ]
    end

    def result(complete:, reason:, required:, complete_keys:, watermarks:)
      incomplete = required - complete_keys
      first_incomplete_at = incomplete.map(&:last).min
      last_delivered_at = watermarks.filter_map(&:last_delivered_at).max
      Result.new(
        complete,
        reason,
        @project_ids,
        @signals,
        @started_at,
        @ended_at,
        required.length,
        complete_keys.length,
        incomplete.first(50).map do |project_id, signal, bucket|
          { project_id:, signal:, bucket_start_at: bucket.utc.iso8601 }
        end,
        complete ? @ended_at : (first_incomplete_at || @started_at),
        last_delivered_at
      )
    end
  end
end
