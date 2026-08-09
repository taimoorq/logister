# frozen_string_literal: true

class TelemetryOutboxEvent < ApplicationRecord
  class SourceRetired < StandardError; end

  RECORD_TYPES = TelemetryIdempotencyKey::RECORD_TYPES

  before_validation :ensure_uuid

  belongs_to :project
  belongs_to :telemetry_idempotency_key
  has_many :telemetry_deliveries, dependent: :destroy

  validates :uuid, :client_identifier, :signal, :record_type, :record_id, :recorded_at, :accepted_at, presence: true
  validates :uuid, uniqueness: true
  validates :telemetry_idempotency_key_id, uniqueness: true
  validates :record_type, inclusion: { in: RECORD_TYPES }

  scope :accepted_between, ->(started_at, ended_at) { where(recorded_at: started_at...ended_at) }

  def source_record
    case record_type
    when "IngestEvent"
      IngestEvent.for_partition_reference(id: record_id, occurred_at: recorded_at)
                 .find_by(project_id: project_id)
    when "TraceSpan"
      TraceSpan.find_by(project_id: project_id, id: record_id)
    end
  end

  def request_context
    raw = metadata.is_a?(Hash) ? metadata.fetch("request_context", {}) : {}
    raw.to_h.symbolize_keys.slice(:ip, :user_agent)
  end

  def repair_deliveries!(destinations, locks_held: false)
    unless locks_held
      return telemetry_idempotency_key.with_lock do
        lock!
        load_locked_deliveries!
        repair_deliveries!(destinations, locks_held: true)
      end
    end

    return [] if source_retired?

    existing = telemetry_deliveries.to_a.index_by(&:destination)
    Array(destinations).map(&:to_s).uniq.sort.map do |destination|
      existing[destination] || ensure_delivery!(destination, locks_held: true)
    end
  end

  def ensure_delivery!(destination, locks_held: false)
    unless locks_held
      return telemetry_idempotency_key.with_lock do
        lock!
        load_locked_deliveries!
        ensure_delivery!(destination, locks_held: true)
      end
    end

    raise SourceRetired, "Source telemetry has been retired; archive replay is required" if source_retired?

    existing = telemetry_deliveries.to_a.find { |delivery| delivery.destination == destination.to_s }
    return existing if existing

    delivery = telemetry_deliveries.create!(
      project: project,
      destination: destination.to_s,
      status: "pending",
      available_at: Time.current
    )
    TelemetryProjectionWatermark.record_accepted!(delivery)
    delivery
  end

  def source_retired?
    telemetry_idempotency_key.source_retired?
  end

  private

  def load_locked_deliveries!
    locked_deliveries = telemetry_deliveries.order(:id).lock.to_a
    delivery_association = association(:telemetry_deliveries)
    delivery_association.target = locked_deliveries
    delivery_association.loaded!
  end

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
