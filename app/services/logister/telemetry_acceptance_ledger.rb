# frozen_string_literal: true

module Logister
  class TelemetryAcceptanceLedger
    class IdentityConflict < StandardError; end

    INSTALLATION_UNRESOLVED = Object.new.freeze

    def self.accept!(record:, client_identifier:, request_context: {}, routing: nil,
                     clickhouse_writable: nil, installation: INSTALLATION_UNRESOLVED,
                     idempotency_key: nil, outbox_event: nil,
                     identity_preloaded: false, locks_held: false)
      new(
        record: record,
        client_identifier: client_identifier,
        request_context: request_context,
        routing: routing,
        clickhouse_writable: clickhouse_writable,
        installation: installation,
        idempotency_key: idempotency_key,
        outbox_event: outbox_event,
        identity_preloaded: identity_preloaded,
        locks_held: locks_held
      ).accept!
    end

    def initialize(record:, client_identifier:, request_context:, routing:, clickhouse_writable:,
                   installation:, idempotency_key:, outbox_event:, identity_preloaded:, locks_held:)
      @record = record
      @client_identifier = TelemetryIdentity.normalize_uuid(client_identifier)
      @request_context = request_context.to_h.symbolize_keys.slice(:ip, :user_agent)
      resolved_installation = if installation.equal?(INSTALLATION_UNRESOLVED)
        Installation.current_if_available
      else
        installation
      end
      @routing = routing || SelfMonitoringPolicy.new(
        project: record.project,
        event: record,
        installation: resolved_installation
      )
      @clickhouse_writable = clickhouse_writable unless clickhouse_writable.nil?
      @idempotency_key = idempotency_key
      @outbox_event = outbox_event
      @identity_preloaded = identity_preloaded
      @locks_held = locks_held
    end

    def accept!
      raise ArgumentError, "A persisted telemetry record is required" unless record.persisted?
      raise ArgumentError, "A UUID telemetry identity is required" unless client_identifier

      key = if @identity_preloaded
        @idempotency_key
      else
        TelemetryIdempotencyKey.find_by(project_id: record.project_id, client_identifier: client_identifier)
      end
      if key && !key.matches_record?(record)
        raise IdentityConflict, "Telemetry identity is already assigned to another record"
      end
      key ||= create_idempotency_key!

      return accept_with_locks!(key) if @locks_held

      key.with_lock { accept_with_locks!(key, acquire_nested_locks: true) }
    end

    def destinations
      if record.is_a?(TraceSpan)
        clickhouse_writable? && routing.mirror_to_clickhouse? ? [ "clickhouse_span" ] : []
      else
        event_destinations
      end
    end

    private

    attr_reader :record, :client_identifier, :request_context, :routing

    def accept_with_locks!(key, acquire_nested_locks: false)
      outbox = @outbox_event || key.telemetry_outbox_event || create_outbox_event!(key)
      if acquire_nested_locks
        outbox.lock!
        locked_deliveries = outbox.telemetry_deliveries.order(:id).lock.to_a
        delivery_association = outbox.association(:telemetry_deliveries)
        delivery_association.target = locked_deliveries
        delivery_association.loaded!
      end
      outbox.repair_deliveries!(destinations, locks_held: true) unless key.source_retired?
      outbox
    end

    def event_destinations
      [].tap do |values|
        values << "clickhouse_event" if clickhouse_writable? && routing.mirror_to_clickhouse?
        if routing.index_deployment? && ProjectDeploymentIndexer.indexable_event?(record)
          values << "deployment_index"
        end
        values << "error_grouping" if record.error?
        values << "check_in_monitor" if record.check_in? && routing.update_check_in_monitor?
      end
    end

    def create_idempotency_key!
      TelemetryIdempotencyKey.create!(
        project_id: record.project_id,
        client_identifier: client_identifier,
        signal: signal,
        record_type: record.class.base_class.name,
        record_id: record.id,
        recorded_at: recorded_at,
        expires_at: Time.current + TelemetryIdempotencyKey::RETENTION,
        acceptance_metadata: acceptance_metadata
      )
    end

    def create_outbox_event!(key)
      TelemetryOutboxEvent.create!(
        project_id: record.project_id,
        telemetry_idempotency_key: key,
        client_identifier: client_identifier,
        signal: signal,
        record_type: record.class.base_class.name,
        record_id: record.id,
        recorded_at: recorded_at,
        accepted_at: record.created_at || Time.current,
        metadata: {
          "schema_version" => 1,
          "record_identifier" => record.uuid,
          "request_context" => request_context.stringify_keys,
          "routing" => {
            "mirror_to_clickhouse" => routing.mirror_to_clickhouse?,
            "index_deployment" => !record.is_a?(TraceSpan) && routing.index_deployment?,
            "send_notifications" => !record.is_a?(TraceSpan) && routing.send_notifications?,
            "update_check_in_monitor" => !record.is_a?(TraceSpan) && routing.update_check_in_monitor?
          }
        }
      )
    end

    def signal
      record.is_a?(TraceSpan) ? "span" : record.event_type.to_s
    end

    def acceptance_metadata
      {
        "schema_version" => 1,
        "record_identifier" => record.uuid,
        "legacy_id" => record.id,
        "record_type" => record.class.base_class.name,
        "recorded_at" => recorded_at.utc.iso8601(6),
        "accepted_at" => (record.created_at || Time.current).utc.iso8601(6),
        "evidence" => evidence_metadata
      }.compact
    end

    def evidence_metadata
      return if record.is_a?(TraceSpan)

      evidence = TelemetryEvidence.for(record)
      {
        "schema_version" => evidence.schema_version,
        "source" => evidence.source,
        "kind" => evidence.kind,
        "evidence_kind" => evidence.evidence_kind,
        "identity_scope" => evidence.identity_scope,
        "time_precision" => evidence.time_precision,
        "occurred_at" => evidence.occurred_at&.utc&.iso8601(6),
        "reporting_start" => evidence.reporting_start&.utc&.iso8601(6),
        "reporting_end" => evidence.reporting_end&.utc&.iso8601(6),
        "received_at" => evidence.received_at&.utc&.iso8601(6)
      }.compact
    end

    def recorded_at
      TelemetryIdempotencyKey.recorded_at_for(record)
    end

    def clickhouse_writable?
      return @clickhouse_writable if defined?(@clickhouse_writable)

      @clickhouse_writable = ClickhouseClient.new.write_enabled?
    end
  end
end
