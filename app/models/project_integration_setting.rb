class ProjectIntegrationSetting < ApplicationRecord
  IMPORT_SCHEDULE_LEASE = 30.minutes
  PROVIDERS = {
    cloudflare_pages: "cloudflare_pages",
    google_play: "google_play",
    app_store_connect: "app_store_connect"
  }.freeze

  belongs_to :project

  before_validation :ensure_uuid
  before_validation :normalize_fields

  enum :provider, PROVIDERS, validate: true, prefix: true

  validates :uuid, presence: true, uniqueness: true
  validates :provider, presence: true, uniqueness: { scope: :project_id }
  validates :account_id, presence: true, if: :provider_cloudflare_pages?
  validates :external_project_name, presence: true, if: :provider_cloudflare_pages?
  validates :external_project_id, :credential_reference, presence: true, if: -> { provider_google_play? && enabled? }
  validates :account_id, :external_project_id, :external_project_name, :credential_reference,
            presence: true,
            if: -> { provider_app_store_connect? && enabled? }
  validate :provider_matches_project_integration

  scope :enabled, -> { where(enabled: true) }
  scope :cloudflare_pages, -> { where(provider: PROVIDERS[:cloudflare_pages]) }
  scope :due_for_import, ->(before: 15.minutes.ago) {
    enabled.where("last_imported_at IS NULL OR last_imported_at <= ?", before)
  }

  def to_param
    uuid
  end

  def self.for(project:, provider:)
    find_or_initialize_by(project: project, provider: provider.to_s)
  end

  def configured?
    case provider
    when PROVIDERS[:cloudflare_pages]
      enabled? && account_id.present? && external_project_name.present? && credential_reference.present?
    when PROVIDERS[:google_play]
      enabled? && external_project_id.present? && credential_reference.present?
    when PROVIDERS[:app_store_connect]
      enabled? && account_id.present? && external_project_id.present? && external_project_name.present? && credential_reference.present?
    else
      enabled?
    end
  end

  def claim_import_schedule!(now: Time.current, lease_for: IMPORT_SCHEDULE_LEASE)
    with_lock do
      schedule = metadata.fetch("import_schedule", {})
      expires_at = Time.zone.parse(schedule["expires_at"].to_s) rescue nil
      return if expires_at&.future?

      token = SecureRandom.uuid
      update!(metadata: metadata.merge(
        "import_schedule" => {
          "token" => token,
          "claimed_at" => now.utc.iso8601,
          "expires_at" => (now + lease_for).utc.iso8601
        }
      ))
      token
    end
  end

  def release_import_schedule!(token:)
    return if token.blank?

    with_lock do
      schedule = metadata.fetch("import_schedule", {})
      return false unless ActiveSupport::SecurityUtils.secure_compare(schedule["token"].to_s, token.to_s)

      next_metadata = metadata.deep_dup
      next_metadata.delete("import_schedule")
      update!(metadata: next_metadata)
      true
    end
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_fields
    self.account_id = account_id.to_s.strip.presence
    self.external_project_id = external_project_id.to_s.strip.presence
    self.external_project_name = external_project_name.to_s.strip.presence
    self.credential_reference = credential_reference.to_s.strip.presence
    self.metadata = metadata.is_a?(Hash) ? metadata : {}
  end

  def provider_matches_project_integration
    return if project.blank? || provider.blank?
    return if provider_cloudflare_pages? && project.integration_cloudflare_pages?
    return if provider_google_play? && project.integration_android?
    return if provider_app_store_connect? && project.integration_ios?

    errors.add(:provider, "does not match this project's integration type")
  end
end
