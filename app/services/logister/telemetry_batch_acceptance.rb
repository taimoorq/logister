# frozen_string_literal: true

module Logister
  class TelemetryBatchAcceptance
    Result = Data.define(:entries, :outbox_events, :rejected) do
      def rejected? = rejected
    end

    def initialize(project:, api_key:, entries:, request_context: {})
      @project = project
      @api_key = api_key
      @entries = Array(entries)
      @request_context = request_context
    end

    def call
      accepted_entries = []
      rejected = false
      resolved_clickhouse_writable = clickhouse_writable?
      resolved_installation = installation

      ApplicationRecord.transaction do
        acquire_identity_locks!
        preload_identity_state!

        entries.each do |entry|
          persistence_result = persist(
            entry,
            clickhouse_writable: resolved_clickhouse_writable,
            installation: resolved_installation
          )
          record = persistence_result.respond_to?(:span) ? persistence_result.span : persistence_result.event
          accepted = record.persisted?
          accepted_entries << {
            entry: entry,
            record: record,
            duplicate: persistence_result.duplicate?,
            outbox_event: persistence_result.outbox_event,
            accepted: accepted,
            errors: accepted ? [] : record.errors.full_messages
          }
          if accepted
            remember_acceptance!(entry, record, persistence_result.outbox_event)
          else
            rejected = true
          end
        end

        raise ActiveRecord::Rollback if rejected
      end

      Result.new(
        accepted_entries,
        accepted_entries.filter_map { |entry| entry.fetch(:outbox_event) }.uniq(&:id),
        rejected
      )
    end

    private

    attr_reader :project, :api_key, :entries, :request_context

    def persist(entry, clickhouse_writable:, installation:)
      options = {
        project: project,
        api_key: api_key,
        attributes: entry.fetch(:attributes),
        request_context: request_context,
        transactional: false,
        acquire_identity_lock: false,
        identity_preloaded: true,
        idempotency_key: key_for(entry),
        existing_record: record_for(entry),
        outbox_event: outbox_for(entry),
        ledger_locks_held: true,
        clickhouse_writable: clickhouse_writable,
        installation: installation
      }
      entry.fetch(:type) == "span" ? TraceSpanPersistence.new(**options).call : IngestEventPersistence.new(**options).call
    end

    def acquire_identity_locks!
      TelemetryIdentityLock.acquire!(
        project_id: project.id,
        client_identifiers: entries.map { |entry| identity_for(entry) }
      )
    end

    def preload_identity_state!
      identities = entries.map { |entry| identity_for(entry) }.uniq
      keys = TelemetryIdempotencyKey.where(project_id: project.id, client_identifier: identities)
                                    .order(:id)
                                    .lock
                                    .to_a
      outboxes = TelemetryOutboxEvent.where(telemetry_idempotency_key_id: keys.map(&:id))
                                     .order(:id)
                                     .lock
                                     .to_a
      deliveries = TelemetryDelivery.where(telemetry_outbox_event_id: outboxes.map(&:id))
                                    .order(:id)
                                    .lock
                                    .to_a
      deliveries_by_outbox_id = deliveries.group_by(&:telemetry_outbox_event_id)
      keys_by_id = keys.index_by(&:id)

      @keys_by_identity = keys.index_by { |key| key.client_identifier.to_s }
      @outboxes_by_identity = outboxes.index_by { |outbox| outbox.client_identifier.to_s }
      @records_by_key_id = load_key_sources(keys)
      @legacy_records = load_legacy_sources(identities - @keys_by_identity.keys)

      outboxes.each do |outbox|
        key_association = outbox.association(:telemetry_idempotency_key)
        key_association.target = keys_by_id.fetch(outbox.telemetry_idempotency_key_id)
        key_association.loaded!
        association = outbox.association(:telemetry_deliveries)
        association.target = deliveries_by_outbox_id.fetch(outbox.id, [])
        association.loaded!
      end
    end

    def load_key_sources(keys)
      event_keys = keys.select { |key| key.record_type == "IngestEvent" }
      span_keys = keys.select { |key| key.record_type == "TraceSpan" }
      event_records = IngestEvent.partition_reference_records(
        event_keys,
        id_key: :record_id,
        occurred_at_key: :recorded_at,
        includes: :project
      ).index_by { |record| [ record.id, record.occurred_at.to_f ] }
      span_records = project.trace_spans.includes(:project).where(id: span_keys.map(&:record_id)).index_by(&:id)

      keys.each_with_object({}) do |key, records|
        records[key.id] = if key.record_type == "IngestEvent"
          event_records[[ key.record_id, key.recorded_at.to_f ]]
        else
          span_records[key.record_id]
        end
      end
    end

    def load_legacy_sources(identities)
      event_identities = identities_for_type("event") & identities
      span_identities = identities_for_type("span") & identities
      {
        "event" => project.ingest_events.includes(:project).where(uuid: event_identities).order(:id)
                          .index_by { |record| record.uuid.to_s },
        "span" => project.trace_spans.includes(:project).where(uuid: span_identities).order(:id)
                         .index_by { |record| record.uuid.to_s }
      }
    end

    def identities_for_type(type)
      entries.filter_map { |entry| identity_for(entry) if entry.fetch(:type) == type }.uniq
    end

    def key_for(entry)
      @keys_by_identity[identity_for(entry)]
    end

    def outbox_for(entry)
      @outboxes_by_identity[identity_for(entry)]
    end

    def record_for(entry)
      key = key_for(entry)
      return @records_by_key_id[key.id] if key

      @legacy_records.fetch(entry.fetch(:type), {})[identity_for(entry)]
    end

    def remember_acceptance!(entry, record, outbox)
      identity = identity_for(entry)
      key = @keys_by_identity[identity] || outbox&.telemetry_idempotency_key
      @keys_by_identity[identity] = key if key
      @outboxes_by_identity[identity] = outbox if outbox
      @records_by_key_id[key.id] = record if key && !record.is_a?(TelemetryAcceptanceTombstone)
      @legacy_records.fetch(entry.fetch(:type), {})[identity] = record unless key
    end

    def identity_for(entry)
      @identity_by_entry ||= {}
      return @identity_by_entry[entry.object_id] if @identity_by_entry.key?(entry.object_id)

      attributes = entry.fetch(:attributes).with_indifferent_access
      raw_identity = attributes[:uuid].presence || attributes[:event_id].presence
      @identity_by_entry[entry.object_id] = Logister::TelemetryIdentity.normalize_uuid(raw_identity) ||
        raise(ArgumentError, "Prepared batch entry is missing a valid stable identity")
    end

    def clickhouse_writable?
      return @clickhouse_writable if defined?(@clickhouse_writable)

      @clickhouse_writable = ClickhouseClient.new.write_enabled?
    end

    def installation
      return @installation if defined?(@installation)

      @installation = Installation.current_if_available
    end
  end
end
