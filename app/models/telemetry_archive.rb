require "digest"

class TelemetryArchive < ApplicationRecord
  OBJECT_ITERATION_BATCH_SIZE = 25
  OBJECT_RESULT_LIMIT = 100

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
  belongs_to :project_retention_run, optional: true
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
    if manifest_version.to_i >= 2 && persisted? && object_record_scope.exists?
      return object_record_scope.order(:sequence, :id).pluck(:object_key)
    end

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
    each_object_record(batch_size: 1).each_with_object([]) do |object_record, references|
      references.concat(object_record.normalized_source_references)
    end
  end

  def object_record_scope
    TelemetryArchiveObject.where(telemetry_archive_id: id)
  end

  def each_object_record(batch_size: OBJECT_ITERATION_BATCH_SIZE)
    return enum_for(__method__, batch_size: batch_size) unless block_given?
    return if new_record?

    slice_size = [ batch_size.to_i, 1 ].max
    last_sequence = -1
    loop do
      records = object_record_scope
        .where("sequence > ?", last_sequence)
        .order(:sequence, :id)
        .limit(slice_size)
        .to_a
      break if records.empty?

      records.each { |object_record| yield object_record }
      last_sequence = records.last.sequence
    end
  end

  # Use this for lifecycle work. It bounds source-reference memory to one
  # manifest object rather than flattening the full tenant archive.
  def each_source_reference_batch
    return enum_for(__method__) unless block_given?

    each_object_record(batch_size: 1) do |object_record|
      yield object_record.normalized_source_references, object_record
    end
  end

  def each_manifest_checksum_chunk
    return enum_for(__method__) unless block_given?

    yield "["
    first = true
    each_object_record(batch_size: 1) do |object_record|
      yield "," unless first
      yield object_record.checksum_attributes.to_json
      first = false
    end
    yield "]"
  end

  def manifest_checksum_sha256
    digest = Digest::SHA256.new
    each_manifest_checksum_chunk { |chunk| digest << chunk }
    digest.hexdigest
  end

  # Compatibility helper for callers that explicitly need the serialized
  # manifest. Lifecycle code should use #manifest_checksum_sha256 so memory is
  # bounded to one object record.
  def manifest_checksum_payload
    each_manifest_checksum_chunk.to_a.join
  end

  def object_summaries(limit: OBJECT_RESULT_LIMIT)
    object_record_scope.order(:sequence, :id).limit([ limit.to_i, 0 ].max).map do |object_record|
      object_summary(object_record)
    end
  end

  def object_summary(object_record)
    {
      "key" => object_record.object_key,
      "rows" => object_record.expected_rows,
      "bytes" => object_record.expected_bytes,
      "checksum_sha256" => object_record.checksum_sha256,
      "source_min_id" => object_record.source_min_id,
      "source_max_id" => object_record.source_max_id,
      "verified_at" => object_record.verified_at&.utc&.iso8601
    }
  end
end
