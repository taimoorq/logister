# frozen_string_literal: true

class TraceSpanPersistence
  Result = Data.define(:span, :duplicate?, :outbox_event)

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

    TraceSpan.transaction(requires_new: true) { perform_call }
  end

  private

  attr_reader :project, :api_key, :attributes, :request_context

  def perform_call
    acquire_idempotency_lock if @acquire_identity_lock
    existing = existing_span
    return duplicate_result(existing) if existing

    span = project.trace_spans.new(attributes.merge(uuid: telemetry_identity))
    span.api_key = api_key
    if span.save
      outbox = accept_record(span)
      Result.new(span, false, outbox)
    else
      Result.new(span, false, nil)
    end
  end

  def raw_client_uuid
    return @raw_client_uuid if defined?(@raw_client_uuid)

    @raw_client_uuid = (attributes[:uuid].presence || attributes[:event_id].presence).to_s.strip.presence
  end

  def client_uuid
    return @client_uuid if defined?(@client_uuid)

    @client_uuid = Logister::TelemetryIdentity.normalize_uuid(raw_client_uuid)
  end

  def telemetry_identity
    @telemetry_identity ||= client_uuid || Logister::TelemetryIdentity.for_span(
      project_id: project.id,
      trace_id: attributes[:trace_id],
      span_id: attributes[:span_id]
    )
  end

  def existing_span
    key = if @identity_preloaded
      @idempotency_key
    else
      TelemetryIdempotencyKey.find_by(project_id: project.id, client_identifier: telemetry_identity)
    end
    if key
      record = @identity_preloaded ? @existing_record : key.accepted_record
      return record if record.is_a?(TraceSpan)
      if record.nil? && key.record_type == "TraceSpan" && key.source_retired?
        return key.acceptance_tombstone(outbox_event: @outbox_event || key.telemetry_outbox_event)
      end

      return identity_conflict_span
    end

    return @existing_record if @identity_preloaded

    project.trace_spans.find_by(uuid: telemetry_identity) ||
      project.trace_spans.find_by(trace_id: attributes[:trace_id], span_id: attributes[:span_id])
  end

  def duplicate_result(span)
    if span.is_a?(TelemetryAcceptanceTombstone)
      return Result.new(span, true, span.outbox_event)
    end
    return Result.new(span, false, nil) unless span.persisted?

    outbox = accept_record(span)
    Result.new(span, true, outbox)
  end

  def accept_record(span)
    Logister::TelemetryAcceptanceLedger.accept!(
      record: span,
      client_identifier: telemetry_identity,
      request_context: request_context,
      clickhouse_writable: @clickhouse_writable,
      installation: @installation,
      idempotency_key: @idempotency_key,
      outbox_event: @outbox_event,
      identity_preloaded: @identity_preloaded,
      locks_held: @ledger_locks_held
    )
  end

  def identity_conflict_span
    span = project.trace_spans.new(attributes.except(:uuid, :event_id))
    span.api_key = api_key
    span.errors.add(:uuid, "has already been used for another telemetry signal")
    span
  end

  def invalid_uuid_result
    span = project.trace_spans.new(attributes.except(:uuid, :event_id))
    span.api_key = api_key
    span.errors.add(:uuid, "is invalid")
    Result.new(span, false, nil)
  end

  def acquire_idempotency_lock
    Logister::TelemetryIdentityLock.acquire!(
      project_id: project.id,
      client_identifiers: [ telemetry_identity ]
    )
  end
end
