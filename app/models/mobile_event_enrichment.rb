# frozen_string_literal: true

class MobileEventEnrichment < ApplicationRecord
  PLATFORMS = %w[android ios].freeze
  KINDS = %w[android_mapping apple_symbolication].freeze
  STATUSES = %w[complete partial artifact_matched verification_pending verification_failed missing build_unknown failed].freeze

  belongs_to :project

  before_validation :ensure_uuid

  validates :uuid, :event_uuid, :event_occurred_at, :platform, :kind, :status,
            :input_sha256, :tool_name, :tool_version, :processed_at, presence: true
  validates :uuid, uniqueness: true
  validates :event_uuid, uniqueness: { scope: %i[project_id kind] }
  validates :platform, inclusion: { in: PLATFORMS }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :input_sha256, :artifact_checksum_sha256,
            format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
  validate :platform_matches_project

  scope :android_mapping, -> { where(platform: "android", kind: "android_mapping") }
  scope :apple_symbolication, -> { where(platform: "ios", kind: "apple_symbolication") }

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def platform_matches_project
    return if project.blank? || platform.blank?
    return if platform == "android" && project.integration_android?
    return if platform == "ios" && project.integration_ios?

    errors.add(:platform, "must match the project integration type")
  end
end
