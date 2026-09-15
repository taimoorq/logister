# frozen_string_literal: true

require "digest"

module TelemetryDeliveryBatches
  extend ActiveSupport::Concern

  class_methods do
    def replay_required_predicate(delivery = arel_table)
      sibling = arel_table.alias("replay_batch_member")
      pending_sibling = Arel::SelectManager.new(sibling).project(Arel.sql("1"))
        .where(sibling[:project_id].eq(delivery[:project_id]))
        .where(sibling[:destination].eq(delivery[:destination]))
        .where(sibling[:batch_key].eq(delivery[:batch_key]))
        .where(sibling[:status].not_eq(statuses.fetch(:completed))).exists
      delivery[:status].not_eq(statuses.fetch(:completed))
        .or(delivery[:batch_key].not_eq(nil).and(pending_sibling))
    end

    # Assignment is all-or-nothing: a stale worker must not pin only part of a
    # chunk, or reuse a key after another owner has grouped its rows differently.
    def assign_batch_key_batch!(deliveries, batch_key:)
      raise ArgumentError, "batch key is required" if batch_key.blank?

      transaction do
        owned = lock_owned_deliveries(deliveries)
        unless owned.length == deliveries.length && owned.all? { |row| row.batch_key.nil? || row.batch_key == batch_key }
          raise TelemetryDelivery::BatchOwnershipLost, "Delivery batch ownership or identity changed"
        end

        where(id: owned.select { |row| row.batch_key.nil? }.map(&:id)).update_all(batch_key: batch_key)
      end
      deliveries.each do |delivery|
        delivery.batch_key = batch_key
        delivery.clear_attribute_changes([ "batch_key" ])
      end
      batch_key
    end

    # Lock before selecting transitions and account for exactly those rows in
    # the same transaction. Already completed or stale-owned rows add nothing.
    def mark_completed_batch!(deliveries, at: Time.current)
      transaction do
        owned = lock_owned_deliveries(deliveries)
        next [] if owned.empty?

        ids = owned.map(&:id)
        changed = where(id: ids).update_all(
          status: statuses.fetch(:completed), completed_at: at, leased_at: nil,
          lease_expires_at: nil, lease_token: nil, available_at: at, updated_at: at
        )
        raise TelemetryDelivery::BatchOwnershipLost, "Delivery completion did not match the locked rows" unless changed == ids.length

        TelemetryProjectionWatermark.record_delivered_batch!(owned, at: at)
        ids
      end
    end

    def renew_batch_lease!(deliveries, at: Time.current, lease_for: TelemetryDelivery::DEFAULT_LEASE)
      transaction(requires_new: true) do
        owned = lock_owned_deliveries(deliveries)
        unless owned.length == deliveries.length && owned.all? { |row| row.lease_expires_at && row.lease_expires_at > at }
          raise TelemetryDelivery::BatchOwnershipLost, "Cannot renew changed or expired delivery ownership"
        end

        where(id: owned.map(&:id)).update_all(lease_expires_at: at + lease_for)
      end
    end

    # Yield only work which this attempt has not started. Preserve batch identity
    # and refund the claim attempt; budget exhaustion is not a delivery failure.
    def release_unstarted_batch!(deliveries, at: Time.current)
      transaction(requires_new: true) do
        owned = lock_owned_deliveries(deliveries).select { |row| row.lease_expires_at && row.lease_expires_at > at }
        where(id: owned.map(&:id)).update_all(status: statuses.fetch(:pending),
          attempts: Arel.sql("GREATEST(attempts - 1, 0)"), available_at: at,
          leased_at: nil, lease_expires_at: nil, lease_token: nil, updated_at: at)
      end
    end

    def claim_batch(limit:, now: Time.current, lease_for: TelemetryDelivery::DEFAULT_LEASE, destinations: TelemetryDelivery::DESTINATIONS, synchronous_limit: nil)
      transaction(requires_new: true) do
        terminal_limit = synchronous_limit ? [ limit, synchronous_limit ].min : limit
        terminalize_expired_final_leases!(now: now, limit: terminal_limit)
        seed = due(now:, destinations:).order(:available_at, :id).first
        next [] unless seed
        # A retry must retain its original deduplication batch. Take its fence
        # before any delivery row, otherwise racing seeds can split the batch.
        next [] if seed.batch_key.present? && !lock_assigned_batch(seed)

        outbox_event = seed.telemetry_outbox_event
        next [] unless outbox_event
        candidates = due(now:, destinations:)
          .where(destination: seed.destination, project_id: seed.project_id)
          .joins(:telemetry_outbox_event)
          .where(telemetry_outbox_events: {
            signal: outbox_event.signal,
            recorded_at: outbox_event.recorded_at.utc.beginning_of_hour...(outbox_event.recorded_at.utc.beginning_of_hour + 1.hour)
          })
        candidates = if seed.batch_key.present?
          candidates.where(batch_key: seed.batch_key).order(:id).lock("FOR UPDATE OF telemetry_deliveries")
        else
          fresh_limit = synchronous_limit && seed.destination.in?(TelemetryDelivery::SYNCHRONOUS_DESTINATIONS) ? [ limit, synchronous_limit ].min : limit
          candidates.where(batch_key: nil).order(:available_at, :id).limit(fresh_limit)
            .lock("FOR UPDATE OF telemetry_deliveries SKIP LOCKED")
        end
        records = candidates.to_a
        next [] if records.empty?

        token = SecureRandom.uuid
        ids = records.map(&:id)
        where(id: ids).update_all(
          status: statuses.fetch(:processing),
          attempts: Arel.sql("attempts + 1"),
          leased_at: now,
          lease_expires_at: now + lease_for,
          lease_token: token,
          updated_at: now
        )
        where(id: ids).includes(:telemetry_outbox_event).order(:id).to_a
      end
    end

    def due(now:, destinations: TelemetryDelivery::DESTINATIONS)
      eligible = joins(:project).where(destination: destinations, projects: { purge_requested_at: nil })
      if ENV["LOGISTER_ORDERED_DELIVERY_CLAIMS"] == "true"
        # Keep the active-state predicate literal so generic prepared plans can
        # use the partial indexes. CASE avoids counting overlapping status
        # predicates independently when estimating the size of a fresh batch.
        return eligible.where(
          <<~SQL.squish, now: now, max_attempts: TelemetryDelivery::MAX_ATTEMPTS
            status IN ('pending', 'retrying', 'processing') AND attempts < :max_attempts
            AND CASE WHEN status = 'processing' THEN lease_expires_at ELSE available_at END <= :now
          SQL
        )
      end

      eligible.where(
        <<~SQL.squish,
          ((status IN (:available_statuses) AND available_at <= :now)
            OR (status = :processing_status AND lease_expires_at <= :now))
          AND attempts < :max_attempts
        SQL
        available_statuses: [ statuses.fetch(:pending), statuses.fetch(:retrying) ],
        processing_status: statuses.fetch(:processing),
        now: now,
        max_attempts: TelemetryDelivery::MAX_ATTEMPTS
      )
    end

    def terminalize_expired_final_leases!(now: Time.current, limit: 100)
      where(status: statuses.fetch(:processing))
        .where("lease_expires_at <= ? AND attempts >= ?", now, TelemetryDelivery::MAX_ATTEMPTS)
        .order(:lease_expires_at, :id)
        .limit(limit)
        .lock("FOR UPDATE OF telemetry_deliveries SKIP LOCKED")
        .each do |delivery|
          delivery.mark_failed!(
            TelemetryDelivery::LeaseExpired.new("Final projector lease expired before acknowledgement"),
            lease_token: delivery.lease_token,
            terminal: true,
            at: now
          )
        end
    end

    private

    def lock_owned_deliveries(deliveries)
      references = deliveries.index_by(&:id)
      raise ArgumentError, "Delivery references must be unique" unless references.length == deliveries.length

      where(id: references.keys).order(:id).lock.includes(:telemetry_outbox_event).select do |row|
        requested = references.fetch(row.id)
        row.project_id == requested.project_id && row.destination == requested.destination &&
          row.send(:owned_processing_lease?, requested.lease_token)
      end
    end

    def lock_assigned_batch(seed)
      identity = "logister:delivery-batch:#{seed.project_id}:#{seed.destination}:#{seed.batch_key}"
      lock_key = Digest::SHA256.digest(identity).unpack1("q>")
      connection.select_value(sanitize_sql_array([ "SELECT pg_try_advisory_xact_lock(?)", lock_key ]))
    end
  end
end
