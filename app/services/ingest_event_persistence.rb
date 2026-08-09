# frozen_string_literal: true

# Persists client events and treats a client-supplied UUID as an idempotency key.
# MetricKit can redeliver a diagnostic, so this prevents retries from inflating
# occurrence, installation, and session impact. The transaction-scoped advisory
# lock closes the concurrent-request race that application-level validation
# cannot close on a range-partitioned table.
class IngestEventPersistence
  Result = Data.define(:event, :duplicate?, :outbox_event)

  def initialize(project:, api_key:, attributes:, request_context: {},
                 transactional: true, acquire_identity_lock: true,
                 identity_preloaded: false, idempotency_key: nil,
                 existing_record: nil, outbox_event: nil,
                 ledger_locks_held: false, clickhouse_writable: nil,
                 installation: Logister::TelemetryAcceptanceLedger::INSTALLATION_UNRESOLVED)
    @project = project
    @api_key = api_key
    @attributes = attributes.to_h.with_indifferent_access
    @request_context = request_context
    @transactional = transactional
    @acquire_identity_lock = acquire_identity_lock
    @identity_preloaded = identity_preloaded
    @idempotency_key = idempotency_key
    @existing_record = existing_record
    @outbox_event = outbox_event
    @ledger_locks_held = ledger_locks_held
    @clickhouse_writable = clickhouse_writable
    @installation = installation
  end

  def call
    return invalid_uuid_result if raw_client_uuid.present? && client_uuid.blank?

    return perform_call unless @transactional

    IngestEvent.transaction(requires_new: true) { perform_call }
  end

  private

  attr_reader :project, :api_key, :attributes, :request_context

  def perform_call
    acquire_idempotency_lock if @acquire_identity_lock && client_uuid.present?
    existing = existing_event
    return duplicate_result(existing) if existing

    persist
  end

  def client_uuid
    return @client_uuid if defined?(@client_uuid)

    @client_uuid = Logister::TelemetryIdentity.normalize_uuid(raw_client_uuid)
  end

  def raw_client_uuid
    return @raw_client_uuid if defined?(@raw_client_uuid)

    @raw_client_uuid = attributes["uuid"].to_s.strip.presence
  end

  def invalid_uuid_result
    event = project.ingest_events.new(attributes.except("uuid"))
    event.api_key = api_key
    event.errors.add(:uuid, "is invalid")
    Result.new(event, false, nil)
  end

  def persist
    event = project.ingest_events.new(attributes)
    event.api_key = api_key
    event.occurred_at ||= Time.current
    if event.save
      outbox = accept_record(event, client_identifier: event.uuid)
      Result.new(event, false, outbox)
    else
      Result.new(event, false, nil)
    end
  end

  def existing_event
    return unless client_uuid.present?

    key = if @identity_preloaded
      @idempotency_key
    else
      TelemetryIdempotencyKey.find_by(project_id: project.id, client_identifier: client_uuid)
    end
    if key
      record = @identity_preloaded ? @existing_record : key.accepted_record
      return record if record.is_a?(IngestEvent)
      if record.nil? && key.record_type == "IngestEvent" && key.source_retired?
        return key.acceptance_tombstone(outbox_event: @outbox_event || key.telemetry_outbox_event)
      end

      return identity_conflict_event
    end

    return @existing_record if @identity_preloaded

    project.ingest_events.find_by(uuid: client_uuid)
  end

  def duplicate_result(event)
    if event.is_a?(TelemetryAcceptanceTombstone)
      return Result.new(event, true, event.outbox_event)
    end
    return Result.new(event, false, nil) unless event.persisted?

    outbox = accept_record(event, client_identifier: client_uuid)
    Result.new(event, true, outbox)
  end

  def accept_record(event, client_identifier:)
    Logister::TelemetryAcceptanceLedger.accept!(
      record: event,
      client_identifier: client_identifier,
      request_context: request_context,
      clickhouse_writable: @clickhouse_writable,
      installation: @installation,
      idempotency_key: @idempotency_key,
      outbox_event: @outbox_event,
      identity_preloaded: @identity_preloaded,
      locks_held: @ledger_locks_held
    )
  end

  def identity_conflict_event
    event = project.ingest_events.new(attributes.except("uuid"))
    event.api_key = api_key
    event.errors.add(:uuid, "has already been used for another telemetry signal")
    event
  end

  def acquire_idempotency_lock
    Logister::TelemetryIdentityLock.acquire!(
      project_id: project.id,
      client_identifiers: [ client_uuid ]
    )
  end
end
