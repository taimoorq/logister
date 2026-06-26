class MobileIngestToken < ApplicationRecord
  DEFAULT_TOKEN_PREFIX = "logister_mobile".freeze
  DEFAULT_EXPIRES_IN_SECONDS = 15.minutes.to_i
  MIN_EXPIRES_IN_SECONDS = 1.minute.to_i
  MAX_EXPIRES_IN_SECONDS = 1.hour.to_i
  REFRESH_SKEW_SECONDS = 60
  PLATFORMS = %w[android ios].freeze
  DEFAULT_ALLOWED_EVENT_TYPES = %w[error log metric transaction span check_in].freeze
  IMMUTABLE_CONTEXT_FIELDS = %w[platform service environment release session_id].freeze

  belongs_to :project
  belongs_to :api_key

  attr_reader :plain_token

  scope :not_revoked, -> { where(revoked_at: nil) }
  scope :not_expired, -> { where("mobile_ingest_tokens.expires_at > ?", Time.current) }

  before_validation :ensure_uuid
  before_validation :ensure_token_digest, on: :create
  before_validation :normalize_fields
  before_validation :normalize_allowed_event_types

  validates :uuid, presence: true, uniqueness: true
  validates :token_digest, presence: true, uniqueness: true
  validates :platform, inclusion: { in: PLATFORMS }
  validates :service, :environment, :expires_at, presence: true
  validate :validate_mobile_ingest_token_constraints

  def self.authenticate(token)
    return nil if token.blank?

    not_revoked
      .not_expired
      .joins(:project, :api_key)
      .merge(Project.active)
      .merge(ApiKey.active)
      .includes(:project, :api_key)
      .find_by(token_digest: digest(token))
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def active?
    revoked_at.nil? &&
      expires_at.present? &&
      expires_at.future? &&
      project.present? &&
      !project.archived? &&
      api_key&.active?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end

  def allows_event_type?(event_type)
    allowed_event_types.include?(normalize_event_type(event_type))
  end

  def context_bindings
    {
      "platform" => platform,
      "service" => service,
      "environment" => environment,
      "release" => release.presence,
      "session_id" => session_id.presence
    }.compact
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def ensure_token_digest
    return if token_digest.present?

    @plain_token = generated_plain_token
    self.token_digest = self.class.digest(@plain_token)
  end

  def generated_plain_token
    [ DEFAULT_TOKEN_PREFIX, SecureRandom.hex(32) ].join("_")
  end

  def normalize_fields
    self.platform = platform.to_s.strip.downcase
    self.service = service.to_s.strip
    self.environment = environment.to_s.strip
    self.release = release.to_s.strip.presence
    self.session_id = session_id.to_s.strip.presence
  end

  def normalize_allowed_event_types
    normalized = Array(allowed_event_types.presence || DEFAULT_ALLOWED_EVENT_TYPES)
                   .map { |event_type| normalize_event_type(event_type) }
                   .reject(&:blank?)
                   .uniq
    self.allowed_event_types = normalized.presence || DEFAULT_ALLOWED_EVENT_TYPES
  end

  def normalize_event_type(event_type)
    event_type.to_s.strip.underscore.downcase
  end

  def validate_mobile_ingest_token_constraints
    MobileIngestTokenValidator.call(self)
  end
end
