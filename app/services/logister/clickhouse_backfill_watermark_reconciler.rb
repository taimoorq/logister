# frozen_string_literal: true

module Logister
  class ClickhouseBackfillWatermarkReconciler
    SOURCE_BATCH_SIZE = 1_000
    SIGNALS = (ClickhouseCoverage::EVENT_SIGNALS + [ "span" ]).freeze

    Result = Data.define(
      :project_id,
      :signal,
      :bucket_start_at,
      :status,
      :postgres_count,
      :clickhouse_count,
      :postgres_checksum,
      :clickhouse_checksum
    ) do
      def verified?
        status == "verified"
      end

      def to_h
        {
          project_id: project_id,
          signal: signal,
          bucket_start_at: bucket_start_at.utc.iso8601,
          status: status,
          postgres_count: postgres_count,
          clickhouse_count: clickhouse_count,
          postgres_checksum: postgres_checksum,
          clickhouse_checksum: clickhouse_checksum
        }
      end
    end

    class << self
      def call(...)
        new(...).call
      end
    end

    def initialize(client:, project_id:, signal:, bucket_start_at:, source_complete: false, now: -> { Time.current })
      @client = client
      @project_id = Integer(project_id)
      @signal = signal.to_s
      @bucket_start_at = bucket_start_at.to_time.utc.beginning_of_hour
      @source_complete = source_complete == true
      @now = now
      raise ArgumentError, "Unsupported telemetry signal: #{@signal}" unless SIGNALS.include?(@signal)
    end

    def call
      clickhouse = clickhouse_fingerprint
      reconcile_with_locked_watermark(clickhouse)
    end

    private

    attr_reader :client, :project_id, :signal, :bucket_start_at

    def reconcile_with_locked_watermark(clickhouse)
      attempts = 0
      begin
        watermark = TelemetryProjectionWatermark.create_or_find_by!(watermark_identity)

        watermark.with_lock do
          unless @source_complete
            watermark.update_column(:complete_at, nil) if watermark.complete_at.present?
            return result("source_baseline_required", clickhouse: clickhouse)
          end

          if incomplete_deliveries?
            watermark.update_column(:complete_at, nil) if watermark.complete_at.present?
            log_blocked_delivery
            return result("incomplete_deliveries", clickhouse: clickhouse)
          end

          postgres = postgres_fingerprint
          if postgres == clickhouse
            publish_complete!(watermark, postgres)
            result("verified", postgres: postgres, clickhouse: clickhouse)
          else
            publish_mismatch!(watermark, postgres, clickhouse)
            log_incomplete("mismatch", postgres: postgres, clickhouse: clickhouse)
            result("mismatch", postgres: postgres, clickhouse: clickhouse)
          end
        end
      rescue ActiveRecord::RecordNotFound
        attempts += 1
        retry if attempts < 3

        raise
      end
    end

    def watermark_identity
      {
        project_id: project_id,
        signal: signal,
        destination: destination,
        bucket_start_at: bucket_start_at
      }
    end

    def destination
      signal == "span" ? "clickhouse_span" : "clickhouse_event"
    end

    def source_scope
      if signal == "span"
        TraceSpan.where(project_id: project_id, started_at: bucket_range)
      else
        IngestEvent.where(project_id: project_id, event_type: signal, occurred_at: bucket_range)
      end
    end

    def postgres_fingerprint
      count = 0
      checksum = 0
      source_scope.in_batches(of: SOURCE_BATCH_SIZE) do |batch|
        identifiers = batch.pluck(:uuid)
        count += identifiers.length
        checksum += identifiers.sum { |identifier| TelemetryProjectionWatermark.identity_checksum(identifier) }
      end
      { count: count, checksum: checksum }
    end

    def clickhouse_fingerprint
      row = client.select_rows!(clickhouse_fingerprint_query).first.to_h
      {
        count: row.fetch("logical_count", 0).to_i,
        checksum: row.fetch("checksum", 0).to_i
      }
    end

    def clickhouse_fingerprint_query
      table_name, time_column = if signal == "span"
        [ client.span_facts_table_name, "started_at" ]
      else
        [ client.event_facts_table_name, "occurred_at" ]
      end
      signal_filter = signal == "span" ? nil : "AND event_type = '#{signal}'"

      <<~SQL.squish
        SELECT
          count() AS logical_count,
          toString(sum(toUInt256(identity_checksum))) AS checksum
        FROM #{table_name}
        WHERE project_id = #{project_id}
          #{signal_filter}
          AND #{time_column} >= parseDateTime64BestEffort('#{bucket_start_at.iso8601(3)}', 3)
          AND #{time_column} < parseDateTime64BestEffort('#{bucket_range.end.iso8601(3)}', 3)
      SQL
    end

    def incomplete_deliveries?
      TelemetryDelivery.incomplete
        .joins(:telemetry_outbox_event)
        .where(project_id: project_id, destination: destination)
        .where(telemetry_outbox_events: { signal: signal, recorded_at: bucket_range })
        .exists?
    end

    def publish_complete!(watermark, fingerprint)
      at = @now.call
      watermark.update!(
        accepted_count: fingerprint.fetch(:count),
        delivered_count: fingerprint.fetch(:count),
        accepted_checksum: fingerprint.fetch(:checksum),
        delivered_checksum: fingerprint.fetch(:checksum),
        terminal_failure_count: 0,
        last_accepted_at: at,
        last_delivered_at: at,
        complete_at: watermark.complete_at || at
      )
    end

    def publish_mismatch!(watermark, postgres, clickhouse)
      at = @now.call
      watermark.update!(
        accepted_count: postgres.fetch(:count),
        delivered_count: clickhouse.fetch(:count),
        accepted_checksum: postgres.fetch(:checksum),
        delivered_checksum: clickhouse.fetch(:checksum),
        last_accepted_at: at,
        last_delivered_at: clickhouse.fetch(:count).positive? ? at : watermark.last_delivered_at,
        complete_at: nil
      )
    end

    def result(status, postgres: nil, clickhouse: nil)
      Result.new(
        project_id,
        signal,
        bucket_start_at,
        status,
        postgres&.fetch(:count),
        clickhouse&.fetch(:count),
        postgres&.fetch(:checksum),
        clickhouse&.fetch(:checksum)
      )
    end

    def log_incomplete(reason, postgres:, clickhouse:)
      Rails.logger.warn(
        "clickhouse_backfill_watermark_incomplete " \
        "project_id=#{project_id} signal=#{signal} bucket=#{bucket_start_at.iso8601} reason=#{reason} " \
        "postgres_count=#{postgres.fetch(:count)} clickhouse_count=#{clickhouse.fetch(:count)}"
      )
    end

    def log_blocked_delivery
      Rails.logger.warn(
        "clickhouse_backfill_watermark_incomplete " \
        "project_id=#{project_id} signal=#{signal} bucket=#{bucket_start_at.iso8601} " \
        "reason=incomplete_deliveries"
      )
    end

    def bucket_range
      bucket_start_at...(bucket_start_at + 1.hour)
    end
  end
end
