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

    # Once retention deletes a source, its outbox row and deliveries have no
    # further use: delivery repair and replay both need the source, and a
    # retried request is answered from the idempotency key's acceptance
    # metadata. The key itself stays until its 120-day expiry. Deleting the
    # outbox row cascades to its deliveries. The caller must hold the key,
    # outbox, and delivery row locks, in that order.
    def self.prune_retired_outbox!(key_ids)
      key_ids = Array(key_ids).compact
      return 0 if key_ids.empty?

      TelemetryOutboxEvent.where(telemetry_idempotency_key_id: key_ids)
                          .where(retired_key_predicate)
                          .where(replay_requirement.arel.exists.not)
                          .delete_all
    end

    # Bounded sweep for outbox rows whose source was retired before retention
    # began pruning them inline. Pass the returned next_after_id to continue.
    def self.prune_retired_backlog(limit:, after_id: 0, batch_size: DEFAULT_BATCH_SIZE, dry_run: true)
      limit = Integer(limit)
      batch_size = batch_size.to_i.clamp(1, 5_000)
      cursor = Integer(after_id.presence || 0)
      scanned = 0
      pruned = 0

      while scanned < limit
        rows = TelemetryOutboxEvent.where(retired_key_predicate)
                                   .where("telemetry_outbox_events.id > ?", cursor)
                                   .order(:id)
                                   .limit([ batch_size, limit - scanned ].min)
                                   .pluck(:id, :telemetry_idempotency_key_id)
        break if rows.empty?

        scanned += rows.size
        cursor = rows.last.first
        key_ids = rows.map(&:last)
        pruned += if dry_run
          TelemetryOutboxEvent.where(id: rows.map(&:first)).where(replay_requirement.arel.exists.not).count
        else
          prune_locked_backlog_batch(key_ids, rows.map(&:first))
        end
      end

      { dry_run: dry_run, scanned_outbox_events: scanned, pruned_outbox_events: pruned, next_after_id: cursor }
    end

    def self.prune_locked_backlog_batch(key_ids, outbox_ids)
      TelemetryIdempotencyKey.transaction do
        TelemetryIdempotencyKey.where(id: key_ids).order(:id).lock.load
        TelemetryOutboxEvent.where(id: outbox_ids).order(:id).lock.load
        TelemetryDelivery.where(telemetry_outbox_event_id: outbox_ids).order(:id).lock.load
        prune_retired_outbox!(key_ids)
      end
    end
    private_class_method :prune_locked_backlog_batch

    def self.retired_key_predicate
      TelemetryIdempotencyKey.where(TelemetryIdempotencyKey.arel_table[:id].eq(TelemetryOutboxEvent.arel_table[:telemetry_idempotency_key_id]))
                             .source_retired
                             .arel.exists
    end
    private_class_method :retired_key_predicate

    def self.replay_requirement
      TelemetryDelivery.where(TelemetryDelivery.arel_table[:telemetry_outbox_event_id].eq(TelemetryOutboxEvent.arel_table[:id]))
                       .required_for_replay
    end
    private_class_method :replay_requirement

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
      TelemetryProjectionBatch.cleanup_completed!
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
      # Start from the bounded expiry candidates and use the unique outbox key
      # lookup. Evaluating replay-group membership over the entire completed
      # delivery history would amplify this new retention protection.
      needed_outbox = TelemetryOutboxEvent.joins(:telemetry_deliveries)
        .where(TelemetryOutboxEvent.arel_table[:telemetry_idempotency_key_id].eq(TelemetryIdempotencyKey.arel_table[:id]))
        .merge(TelemetryDelivery.required_for_replay)

      TelemetryIdempotencyKey.expired(expired_before)
        .where(needed_outbox.arel.exists.not)
        .order(:expires_at, :id)
    end

    def delete_if_complete(id)
      key = TelemetryIdempotencyKey.find_by(id: id)
      return false unless key

      key.with_lock do
        return false if key.telemetry_outbox_event&.telemetry_deliveries&.required_for_replay&.exists?

        key.destroy!
      end
      true
    end
  end
end
