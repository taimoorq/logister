# frozen_string_literal: true

class TelemetryArchiveObject < ApplicationRecord
  STATUSES = %w[pending uploading uploaded verifying verified failed deleted].freeze

  belongs_to :telemetry_archive, inverse_of: :object_records

  validates :sequence, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sequence, uniqueness: { scope: :telemetry_archive_id }
  validates :status, inclusion: { in: STATUSES }
  validates :object_key, :content_type, :checksum_sha256, :checksum_md5_base64, presence: true
  validates :object_key, uniqueness: true
  validates :expected_rows, :expected_bytes,
            :source_min_id, :source_max_id,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :verified_rows, :verified_bytes, :attempts,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :source_range_is_ordered
  validate :source_references_match_expected_rows

  scope :ordered, -> { order(:sequence) }
  scope :verified, -> { where(status: "verified") }

  validate :storage_generation_matches_locator

  def normalized_source_references
    Array(source_references).filter_map do |reference|
      next unless reference.respond_to?(:[])

      id = reference["id"] || reference[:id]
      next if id.blank?

      timestamp = reference["timestamp"] || reference[:timestamp]
      { "id" => id.to_i, "timestamp" => timestamp.presence }
    end
  end

  def checksum_attributes
    attributes = {
      "sequence" => sequence,
      "object_key" => object_key,
      "checksum_sha256" => checksum_sha256,
      "expected_rows" => expected_rows,
      "expected_bytes" => expected_bytes,
      "source_references" => normalized_source_references
    }
    attributes["storage_generation"] = storage_generation if storage_generation.present?
    attributes["object_version_id"] = object_version_id if object_version_id.present?
    attributes
  end

  def verified?
    status == "verified"
  end

  private

  def storage_generation_matches_locator
    return if storage_locator.blank? && storage_generation.blank?
    return if storage_locator.is_a?(Hash) && storage_locator["generation_id"] == storage_generation

    errors.add(:storage_generation, "must match the immutable storage locator")
  end

  def source_range_is_ordered
    return if source_min_id.blank? || source_max_id.blank? || source_min_id <= source_max_id

    errors.add(:source_max_id, "must be greater than or equal to source_min_id")
  end

  def source_references_match_expected_rows
    return if source_references.blank? && expected_rows.to_i.zero?
    return if normalized_source_references.size == expected_rows.to_i

    errors.add(:source_references, "must contain one exact reference per expected row")
  end
end
