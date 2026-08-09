class TelemetryArchive < ApplicationRecord
  RECORD_TYPES = %w[ingest_events trace_spans].freeze
  STATUSES = %w[
    pending
    uploading
    verifying
    completed
    failed
    restoring
    restored
    deleting
    deleted
  ].freeze

  belongs_to :project
  has_many :object_records,
           -> { order(:sequence) },
           class_name: "TelemetryArchiveObject",
           dependent: :destroy,
           inverse_of: :telemetry_archive

  validates :record_type, presence: true, inclusion: { in: RECORD_TYPES }
  validates :scope, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :before_at, presence: true
  validates :rows, :bytes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :completed, -> { where(status: %w[completed restored]) }
  scope :failed, -> { where(status: "failed") }
  scope :resumable, -> { where(status: %w[pending uploading verifying failed]) }
  scope :verified, -> { where(status: %w[completed restored]).where.not(verified_at: nil) }
  scope :awaiting_source_cleanup, -> { verified.where(source_deleted_at: nil) }
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
    status.in?(%w[completed restored])
  end

  def failed?
    status == "failed"
  end

  def verified?
    status.in?(%w[completed restored]) && verified_at.present?
  end

  def exact_source_references
    object_records.reorder(:id).find_each(batch_size: 1).each_with_object([]) do |object_record, references|
      references.concat(object_record.normalized_source_references)
    end
  end

  # Use this for lifecycle work. It bounds source-reference memory to one
  # manifest object rather than flattening the full tenant archive.
  def each_source_reference_batch
    return enum_for(__method__) unless block_given?

    object_records.reorder(:id).find_each(batch_size: 1) do |object_record|
      yield object_record.normalized_source_references, object_record
    end
  end

  def manifest_checksum_payload
    object_records.map(&:checksum_attributes).to_json
  end
end
