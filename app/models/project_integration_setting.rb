class ProjectIntegrationSetting < ApplicationRecord
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
    else
      enabled?
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
