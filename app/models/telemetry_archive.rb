class TelemetryArchive < ApplicationRecord
  RECORD_TYPES = %w[ingest_events trace_spans].freeze
  STATUSES = %w[completed failed].freeze

  belongs_to :project

  validates :record_type, presence: true, inclusion: { in: RECORD_TYPES }
  validates :scope, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :before_at, presence: true
  validates :rows, :bytes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :completed, -> { where(status: "completed") }
  scope :recent_first, -> { order(created_at: :desc) }

  def archive_objects
    objects.is_a?(Array) ? objects : []
  end

  def object_keys
    archive_objects.filter_map do |object|
      next unless object.respond_to?(:[])

      object["key"].presence || object[:key].presence
    end
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end
end
