class Project < ApplicationRecord
  include ProjectAccess

  DEFAULT_PUBLIC_API_RATE_LIMIT_REQUESTS = 1_200
  DEFAULT_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS = 60
  DEFAULT_PUBLIC_API_PRE_AUTH_RATE_LIMIT_REQUESTS = 12_000
  DEFAULT_PUBLIC_API_AUTH_FAILURE_RATE_LIMIT_REQUESTS = 120
  MIN_PUBLIC_API_RATE_LIMIT_REQUESTS = 1
  MAX_PUBLIC_API_RATE_LIMIT_REQUESTS = 10_000_000
  MIN_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS = 1
  MAX_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS = 86_400
  INTEGRATION_LABELS = ProjectIntegrationDefinition.all.to_h do |definition|
    [ definition.key, definition.label ]
  end.freeze
  @integration_options = ProjectIntegrationDefinition.all_for_picker.map do |definition|
    [ definition.picker_label, definition.key ].freeze
  end.freeze

  class << self
    attr_reader :integration_options

    delegate :default_public_api_rate_limit_requests,
             :default_public_api_rate_limit_period_seconds,
             :default_public_api_pre_auth_rate_limit_requests,
             :default_public_api_auth_failure_rate_limit_requests,
             to: "ProjectRateLimits"
    delegate :stats_for,
             :latest_event_at_by_project,
             to: "ProjectStats"
  end

  delegate :public_api_rate_limit_requests_effective,
           :public_api_rate_limit_period_seconds_effective,
           :public_api_auth_failure_rate_limit_requests_effective,
           to: :rate_limits

  belongs_to :user
  has_many :api_keys, dependent: :destroy
  has_many :mobile_ingest_tokens, dependent: :destroy
  has_many :ingest_events, dependent: :destroy
  has_many :trace_spans, dependent: :destroy
  has_many :error_groups, dependent: :destroy
  has_many :check_in_monitors, dependent: :destroy
  has_many :project_memberships, dependent: :destroy
  has_many :project_notification_preferences, dependent: :destroy
  has_many :integration_settings, class_name: "ProjectIntegrationSetting", dependent: :destroy
  has_many :android_mapping_files, dependent: :destroy
  has_many :apple_symbol_artifacts, dependent: :destroy
  has_many :mobile_event_enrichments, dependent: :destroy
  has_many :evidence_access_audits, dependent: :delete_all
  has_many :source_repositories, class_name: "ProjectSourceRepository", dependent: :destroy
  has_many :project_github_installations, dependent: :destroy
  has_many :github_installations, through: :project_github_installations
  has_many :deployments, class_name: "ProjectDeployment", dependent: :destroy
  has_many :email_notification_deliveries, dependent: :destroy
  has_many :notification_intents, dependent: :destroy
  has_one :self_monitoring_installation,
          class_name: "Installation",
          foreign_key: :self_monitoring_project_id,
          dependent: :nullify,
          inverse_of: :self_monitoring_project
  has_one :retention_policy, class_name: "ProjectRetentionPolicy", dependent: :destroy
  has_many :retention_runs, class_name: "ProjectRetentionRun", dependent: :destroy
  has_many :telemetry_archives, dependent: :destroy
  has_many :project_purges, dependent: :nullify
  has_many :members, through: :project_memberships, source: :user

  accepts_nested_attributes_for :retention_policy

  before_validation :ensure_uuid
  before_validation :normalize_slug
  before_destroy :require_purge_execution

  validate :integration_kind_cannot_change, on: :update

  enum :integration_kind, {
    ruby: "ruby",
    cfml: "cfml",
    javascript: "javascript",
    python: "python",
    dotnet: "dotnet",
    cloudflare_pages: "cloudflare_pages",
    android: "android",
    ios: "ios",
    http_api: "http_api"
  }, default: :ruby, validate: true, prefix: :integration

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :accessible_to, lambda { |user|
    if user
      shared_project_ids = ProjectMembership.where(user_id: user.id).select(:project_id)
      where(user_id: user.id).or(where(id: shared_project_ids))
    else
      none
    end
  }
  scope :manageable_by, lambda { |user|
    if user
      admin_project_ids = ProjectMembership.admin.where(user_id: user.id).select(:project_id)
      where(user_id: user.id).or(where(id: admin_project_ids))
    else
      none
    end
  }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id }
  validates :uuid, presence: true, uniqueness: true
  validates :public_api_rate_limit_requests_override,
            :public_api_auth_failure_rate_limit_requests_override,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: MIN_PUBLIC_API_RATE_LIMIT_REQUESTS,
              less_than_or_equal_to: MAX_PUBLIC_API_RATE_LIMIT_REQUESTS
            },
            allow_nil: true
  validates :public_api_rate_limit_period_seconds_override,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: MIN_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS,
              less_than_or_equal_to: MAX_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS
            },
            allow_nil: true

  def to_param
    uuid
  end

  def archived?
    archived_at.present?
  end

  def purge_pending?
    purge_requested_at.present?
  end

  def notifications_disabled?
    archived? || purge_pending?
  end

  def archive!
    archive_time = Time.current

    transaction do
      update!(archived_at: archive_time)
      api_keys.active.update_all(revoked_at: archive_time, updated_at: archive_time)
    end
  end

  def restore!
    if purge_pending?
      errors.add(:base, "cannot restore a project after permanent deletion has been requested")
      raise ActiveRecord::RecordInvalid, self
    end

    update!(archived_at: nil)
  end

  def destroy_for_purge!
    unless purge_pending? && project_purges.exists?
      errors.add(:base, "requires a durable project purge ledger before deletion")
      raise ActiveRecord::RecordInvalid, self
    end

    @purge_execution_authorized = true
    destroy!
  ensure
    @purge_execution_authorized = false
  end

  def integration_label
    INTEGRATION_LABELS.fetch(integration_kind, integration_kind.to_s.humanize)
  end

  def integration_definition
    ProjectIntegrationDefinition.fetch(integration_kind)
  end

  def self_monitoring_for?(installation = Installation.current_if_available)
    installation&.self_monitoring_project_id == id
  end

  private

  def rate_limits
    @rate_limits ||= ProjectRateLimits.new(self)
  end

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_slug
    base = slug.presence || name
    self.slug = base.to_s.parameterize
  end

  def integration_kind_cannot_change
    return unless will_save_change_to_integration_kind?

    errors.add(:integration_kind, "cannot be changed after project creation")
  end

  def require_purge_execution
    return if @purge_execution_authorized

    errors.add(:base, "Must be deleted through the audited project purge lifecycle")
    throw :abort
  end
end
