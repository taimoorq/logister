# frozen_string_literal: true

class TelemetryIdempotencyKey < ApplicationRecord
  RETENTION = 120.days
  RECORD_TYPES = %w[IngestEvent TraceSpan].freeze

  belongs_to :project
  has_one :telemetry_outbox_event, dependent: :destroy

  attr_readonly :project_id,
                :client_identifier,
                :signal,
                :record_type,
                :record_id,
                :recorded_at,
                :acceptance_metadata

  validates :client_identifier, :signal, :record_type, :record_id, :recorded_at, :expires_at, presence: true
  validates :client_identifier, uniqueness: { scope: :project_id }
  validates :record_type, inclusion: { in: RECORD_TYPES }

  scope :expired, ->(at = Time.current) { where(expires_at: ...at) }
  scope :source_retired, -> { where.not(source_retired_at: nil) }

  def accepted_record
    case record_type
    when "IngestEvent"
      IngestEvent.for_partition_reference(id: record_id, occurred_at: recorded_at)
                 .find_by(project_id: project_id)
    when "TraceSpan"
      TraceSpan.find_by(project_id: project_id, id: record_id)
    end
  end

  def matches_record?(record)
    project_id == record.project_id &&
      record_type == record.class.base_class.name &&
      record_id == record.id &&
      recorded_at.to_f == self.class.recorded_at_for(record).to_f
  end

  def source_retired? = source_retired_at.present?

  def acceptance_tombstone(outbox_event: telemetry_outbox_event)
    TelemetryAcceptanceTombstone.new(idempotency_key: self, outbox_event: outbox_event)
  end

  def self.for_source_references(project_id:, record_type:, references:, id_key:, recorded_at_key:)
    pairs = Array(references).filter_map do |reference|
      id = source_reference_value(reference, id_key)
      recorded_at = source_reference_value(reference, recorded_at_key)
      [ id, recorded_at ] if id.present? && recorded_at.present?
    end.uniq
    return none if pairs.empty?

    table = arel_table
    identity_condition = pairs.map do |id, recorded_at|
      table[:record_id].eq(id).and(table[:recorded_at].eq(recorded_at))
    end.reduce { |left, right| left.or(right) }
    where(project_id: project_id, record_type: record_type).where(identity_condition)
  end

  def self.source_reference_value(reference, key)
    return reference.public_send(key) if reference.respond_to?(key)
    return unless reference.respond_to?(:[])

    reference[key] || reference[key.to_s]
  end
  private_class_method :source_reference_value

  def self.recorded_at_for(record)
    record.is_a?(TraceSpan) ? record.started_at : record.occurred_at
  end
end
