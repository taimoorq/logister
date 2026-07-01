# frozen_string_literal: true

class CliAccessToken < ApplicationRecord
  DEFAULT_TOKEN_PREFIX = "logister_cli"
  DEFAULT_EXPIRES_IN = 30.days
  MAX_EXPIRES_IN = 1.year

  READ_SCOPES = %w[
    projects:read
    project_summary:read
    events:read
    errors:read
    ai_context:read
  ].freeze

  SCOPES = (READ_SCOPES + %w[
    traces:read
    monitors:read
    deployments:read
    insights:read
    metrics:read
    errors:write
  ]).freeze

  belongs_to :user

  attr_reader :plain_token

  before_validation :ensure_uuid
  before_validation :ensure_token_digest, on: :create
  before_validation :normalize_fields

  validates :uuid, :name, :token_digest, :expires_at, presence: true
  validates :uuid, :token_digest, uniqueness: true
  validate :scopes_are_supported
  validate :allowed_projects_are_accessible
  validate :expiration_is_within_bounds, on: :create

  scope :not_revoked, -> { where(revoked_at: nil) }
  scope :not_expired, -> { where("cli_access_tokens.expires_at > ?", Time.current) }
  scope :active, -> { not_revoked.not_expired }

  def self.authenticate(token)
    return nil if token.blank?

    active.includes(:user).find_by(token_digest: digest(token))
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def active?
    revoked_at.blank? && expires_at.present? && expires_at.future?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end

  def allows_scope?(scope)
    scopes.include?(scope.to_s)
  end

  def allows_scopes?(*required_scopes)
    required_scopes.all? { |scope| allows_scope?(scope) }
  end

  def accessible_projects
    relation = user.accessible_projects
    return relation if all_projects?

    relation.where(id: allowed_project_ids)
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def ensure_token_digest
    return if token_digest.present?

    @plain_token = [ token_prefix, SecureRandom.hex(32) ].join("_")
    self.token_digest = self.class.digest(@plain_token)
  end

  def normalize_fields
    self.name = name.to_s.strip.presence
    self.scopes = Array(scopes).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    self.allowed_project_ids = Array(allowed_project_ids).filter_map { |id| Integer(id, exception: false) }.uniq
    self.expires_at ||= DEFAULT_EXPIRES_IN.from_now
  end

  def token_prefix
    ENV.fetch("LOGISTER_CLI_TOKEN_PREFIX", DEFAULT_TOKEN_PREFIX)
  end

  def scopes_are_supported
    unknown = scopes - SCOPES
    errors.add(:scopes, "contains unsupported values: #{unknown.join(', ')}") if unknown.any?
    errors.add(:scopes, "must include at least one scope") if scopes.empty?
  end

  def allowed_projects_are_accessible
    return if all_projects?
    return errors.add(:allowed_project_ids, "must include at least one project unless all_projects is enabled") if allowed_project_ids.empty?
    return unless user

    accessible_ids = user.accessible_projects.where(id: allowed_project_ids).pluck(:id)
    inaccessible_ids = allowed_project_ids - accessible_ids
    errors.add(:allowed_project_ids, "contains inaccessible projects: #{inaccessible_ids.join(', ')}") if inaccessible_ids.any?
  end

  def expiration_is_within_bounds
    return if expires_at.blank?

    if expires_at <= Time.current
      errors.add(:expires_at, "must be in the future")
    elsif expires_at > MAX_EXPIRES_IN.from_now
      errors.add(:expires_at, "must be within #{MAX_EXPIRES_IN.inspect}")
    end
  end
end
