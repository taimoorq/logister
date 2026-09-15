# frozen_string_literal: true

module TelemetryProjectionRecording
  extend ActiveSupport::Concern

  PROGRESS_INCREMENT_SQL = <<~SQL.squish.freeze
    accepted_count = telemetry_projection_watermarks.accepted_count + EXCLUDED.accepted_count,
    accepted_checksum = telemetry_projection_watermarks.accepted_checksum + EXCLUDED.accepted_checksum,
    delivered_count = telemetry_projection_watermarks.delivered_count + EXCLUDED.delivered_count,
    delivered_checksum = telemetry_projection_watermarks.delivered_checksum + EXCLUDED.delivered_checksum,
    last_accepted_at = GREATEST(telemetry_projection_watermarks.last_accepted_at, EXCLUDED.last_accepted_at),
    last_delivered_at = GREATEST(telemetry_projection_watermarks.last_delivered_at, EXCLUDED.last_delivered_at),
    updated_at = GREATEST(telemetry_projection_watermarks.updated_at, EXCLUDED.updated_at),
    complete_at = CASE WHEN
      (telemetry_projection_watermarks.accepted_count + EXCLUDED.accepted_count > 0
        OR telemetry_projection_watermarks.complete_at IS NOT NULL)
      AND telemetry_projection_watermarks.accepted_count + EXCLUDED.accepted_count
        = telemetry_projection_watermarks.delivered_count + EXCLUDED.delivered_count
      AND telemetry_projection_watermarks.accepted_checksum + EXCLUDED.accepted_checksum
        = telemetry_projection_watermarks.delivered_checksum + EXCLUDED.delivered_checksum
      AND telemetry_projection_watermarks.terminal_failure_count = 0
      THEN COALESCE(telemetry_projection_watermarks.complete_at, EXCLUDED.updated_at)
      ELSE NULL END
  SQL

  class_methods do
    def record_accepted!(delivery, at: Time.current)
      record_accepted_batch!([ [ delivery, at ] ])
    end

    def record_accepted_batch!(acceptances)
      record_progress!(acceptances, kind: :accepted)
    end

    def record_delivered!(delivery, at: Time.current)
      record_delivered_batch!([ delivery ], at: at)
    end

    def record_delivered_batch!(deliveries, at: Time.current)
      record_progress!(deliveries.map { |delivery| [ delivery, at ] }, kind: :delivered)
    end

    def identity_checksum(client_identifier)
      client_identifier.to_s.delete("-").to_i(16)
    end

    private

    def record_progress!(entries, kind:)
      return if entries.empty?

      buckets = entries.group_by { |delivery, _at| identity_for_delivery(delivery) }
      rows = buckets.map do |identity, values|
        checksum = values.sum { |delivery, _at| identity_checksum_for(delivery) }
        # UUID sums exceed bigint. This numeric literal is derived only from
        # integer arithmetic, and bypasses Rails' 64-bit integer quoting limit.
        checksum_literal = Arel.sql(checksum.to_s)
        first_at, last_at = values.map(&:last).minmax
        identity.merge(
          accepted_count: kind == :accepted ? values.length : 0,
          accepted_checksum: kind == :accepted ? checksum_literal : 0,
          delivered_count: kind == :delivered ? values.length : 0,
          delivered_checksum: kind == :delivered ? checksum_literal : 0,
          last_accepted_at: kind == :accepted ? last_at : nil,
          last_delivered_at: kind == :delivered ? last_at : nil,
          created_at: first_at,
          updated_at: last_at
        )
      end
      # Every batch visits shared buckets in the same order, even when clients
      # send signals or hours in opposite orders. Counts and completion move in
      # one atomic statement; there is no exception-driven lookup or reload.
      rows.sort_by! { |row| row.values_at(:project_id, :signal, :destination, :bucket_start_at) }
      upsert_all(rows, unique_by: :idx_telemetry_watermarks_bucket,
        on_duplicate: Arel.sql(PROGRESS_INCREMENT_SQL), returning: false)
    end

    def identity_checksum_for(delivery)
      outbox_event = delivery.telemetry_outbox_event
      record_identifier = outbox_event.metadata.to_h["record_identifier"].presence || outbox_event.client_identifier
      identity_checksum(record_identifier)
    end

    def identity_for_delivery(delivery)
      outbox_event = delivery.telemetry_outbox_event
      {
        project_id: delivery.project_id,
        signal: outbox_event.signal,
        destination: delivery.destination,
        bucket_start_at: outbox_event.recorded_at.utc.beginning_of_hour
      }
    end
  end
end
