# frozen_string_literal: true

class AppleSymbolArtifact < ApplicationRecord
  MAX_BYTES = 500.megabytes
  STATUSES = %w[uploaded processing verified awaiting_tooling failed].freeze
  ARCHITECTURES = %w[arm64 arm64e x86_64 armv7].freeze
  UUID_PATTERN = /\A[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\z/

  belongs_to :project
  belongs_to :uploaded_by, class_name: "User", optional: true

  before_validation :ensure_uuid
  before_validation :normalize_fields

  validates :uuid, :app_identifier, :version_code, :binary_uuid, :architecture,
            :checksum_sha256, :filename, :storage_key, :status, presence: true
  validates :uuid, uniqueness: true
  validates :binary_uuid, format: { with: UUID_PATTERN }
  validates :architecture, inclusion: { in: ARCHITECTURES }
  validates :status, inclusion: { in: STATUSES }
  validates :checksum_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :byte_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_BYTES }
  validates :checksum_sha256, uniqueness: { scope: %i[project_id binary_uuid architecture] }
  validate :ios_project

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :usable, -> { where(status: "verified") }

  after_destroy_commit :delete_private_object

  def to_param
    uuid
  end

  def verified?
    status == "verified"
  end

  def verification_label
    {
      "uploaded" => "Uploaded",
      "processing" => "Verifying UUIDs",
      "verified" => "UUID verified",
      "awaiting_tooling" => "Verification blocked",
      "failed" => "Verification failed"
    }.fetch(status)
  end

  def processable?
    %w[uploaded awaiting_tooling failed].include?(status)
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_fields
    self.app_identifier = app_identifier.to_s.strip
    self.version_name = version_name.to_s.strip.presence
    self.version_code = version_code.to_s.strip
    self.release = release.to_s.strip.presence
    self.binary_uuid = binary_uuid.to_s.delete("{}").upcase
    self.architecture = architecture.to_s.strip.downcase
    self.filename = filename.to_s.strip
    self.content_type = content_type.to_s.strip.presence
    self.storage_key = storage_key.to_s.delete_prefix("/")
    self.status = status.to_s.presence || "uploaded"
    self.metadata = metadata.is_a?(Hash) ? metadata : {}
  end

  def ios_project
    errors.add(:project, "must be an iOS project") unless project&.integration_ios?
  end

  def delete_private_object
    locator = metadata.is_a?(Hash) ? metadata["storage_locator"] : nil
    service = InstanceConfiguration::ArchiveService.build(locator: locator)
    InstanceConfiguration::ArchiveService.delete_all_versions!(service, storage_key)
  rescue StandardError => error
    Rails.logger.warn("apple symbol object delete failed key=#{storage_key.inspect}: #{error.class} #{error.message}")
  end
end
