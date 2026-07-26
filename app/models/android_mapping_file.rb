# frozen_string_literal: true

require "digest"

class AndroidMappingFile < ApplicationRecord
  MAX_BYTES = 20.megabytes

  belongs_to :project
  belongs_to :uploaded_by, class_name: "User", optional: true

  before_validation :ensure_uuid
  before_validation :normalize_fields

  validates :uuid, :package_name, :version_code, :checksum_sha256, presence: true
  validates :uuid, uniqueness: true
  validates :version_code, uniqueness: { scope: %i[project_id package_name] }
  validates :byte_size, numericality: { greater_than: 0, less_than_or_equal_to: MAX_BYTES }
  validate :android_project
  validate :mapping_content_shape

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def to_param
    uuid
  end

  def upload=(uploaded_file)
    return if uploaded_file.blank?

    bytes = uploaded_file.read(MAX_BYTES + 1)
    self.content = bytes
    self.byte_size = bytes.bytesize
    self.checksum_sha256 = Digest::SHA256.hexdigest(bytes)
    self.metadata = metadata.merge("filename" => uploaded_file.original_filename.to_s, "content_type" => uploaded_file.content_type.to_s)
  ensure
    uploaded_file.rewind if uploaded_file.respond_to?(:rewind)
  end

  def filename
    metadata["filename"].presence || "mapping-#{version_code}.txt"
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_fields
    self.package_name = package_name.to_s.strip
    self.version_name = version_name.to_s.strip.presence
    self.version_code = version_code.to_s.strip
    self.release = release.to_s.strip.presence
    self.metadata = metadata.is_a?(Hash) ? metadata : {}
  end

  def android_project
    errors.add(:project, "must be an Android project") unless project&.integration_android?
  end

  def mapping_content_shape
    return if content.blank? || byte_size.to_i > MAX_BYTES
    return if content.to_s.each_line.first(200).any? { |line| line.match?(/\A\S.+ -> \S+:\s*\z/) }

    errors.add(:content, "does not look like an R8/ProGuard mapping file")
  end
end
