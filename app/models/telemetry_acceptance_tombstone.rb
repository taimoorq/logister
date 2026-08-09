# frozen_string_literal: true

class TelemetryAcceptanceTombstone
  include ActiveModel::Model

  attr_reader :project_id, :uuid, :record_id, :record_type, :recorded_at, :accepted_at, :outbox_event

  def initialize(idempotency_key:, outbox_event: idempotency_key.telemetry_outbox_event)
    metadata = idempotency_key.acceptance_metadata.to_h
    @project_id = idempotency_key.project_id
    @uuid = metadata["record_identifier"].presence || idempotency_key.client_identifier
    @record_id = metadata["legacy_id"].presence || idempotency_key.record_id
    @record_type = idempotency_key.record_type
    @recorded_at = metadata["recorded_at"].presence || idempotency_key.recorded_at
    @accepted_at = metadata["accepted_at"].presence || outbox_event&.accepted_at
    @outbox_event = outbox_event
  end

  alias_method :id, :record_id

  def persisted? = true
  def source_retired? = true
end
