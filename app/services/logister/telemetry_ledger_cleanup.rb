# frozen_string_literal: true

module Logister
  class TelemetryLedgerCleanup
    DEFAULT_BATCH_SIZE = 500

    def self.call(expired_before: Time.current, batch_size: DEFAULT_BATCH_SIZE, watermarks_before: nil)
      new(
        expired_before: expired_before,
        batch_size: batch_size,
        watermarks_before: watermarks_before || expired_before - TelemetryProjectionWatermark::RETENTION
      ).call
    end

    def initialize(expired_before:, batch_size:, watermarks_before:)
      @expired_before = expired_before
      @batch_size = batch_size.to_i.clamp(1, 5_000)
      @watermarks_before = watermarks_before
    end

    def call
      deleted = 0
      loop do
        ids = cleanup_candidates.limit(batch_size).pluck(:id)
        break if ids.empty?

        removed_this_batch = ids.count { |id| delete_if_complete(id) }
        deleted += removed_this_batch
        break if removed_this_batch.zero?
      end
      cleanup_watermarks
      deleted
    end

    private

    attr_reader :expired_before, :batch_size, :watermarks_before

    def cleanup_watermarks
      TelemetryProjectionWatermark.where(bucket_start_at: ...watermarks_before)
        .find_in_batches(batch_size: batch_size) do |watermarks|
          watermarks.each { |watermark| delete_watermark_if_inactive(watermark) }
        end
    end

    def delete_watermark_if_inactive(watermark)
      watermark.with_lock do
        return if incomplete_delivery_for?(watermark)

        watermark.destroy!
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def incomplete_delivery_for?(watermark)
      TelemetryDelivery.incomplete
        .joins(:telemetry_outbox_event)
        .where(project_id: watermark.project_id, destination: watermark.destination)
        .where(
          telemetry_outbox_events: {
            signal: watermark.signal,
            recorded_at: watermark.bucket_start_at...(watermark.bucket_start_at + 1.hour)
          }
        )
        .exists?
    end

    def cleanup_candidates
      incomplete_key_ids = TelemetryDelivery.incomplete
        .joins(:telemetry_outbox_event)
        .select("telemetry_outbox_events.telemetry_idempotency_key_id")

      TelemetryIdempotencyKey.expired(expired_before)
        .where.not(id: incomplete_key_ids)
        .order(:expires_at, :id)
    end

    def delete_if_complete(id)
      key = TelemetryIdempotencyKey.find_by(id: id)
      return false unless key

      key.with_lock do
        return false if key.telemetry_outbox_event&.telemetry_deliveries&.incomplete&.exists?

        key.destroy!
      end
      true
    end
  end
end
