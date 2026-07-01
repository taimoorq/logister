# frozen_string_literal: true

class CliDeviceAuthorization < ApplicationRecord
  DEFAULT_EXPIRES_IN = 10.minutes
  DEFAULT_INTERVAL_SECONDS = 3
  USER_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze

  ExchangeResult = Data.define(:status, :access_token) do
    def access_token? = access_token.present?
  end

  belongs_to :user, optional: true
  belongs_to :cli_access_token, optional: true

  enum :status, { pending: 0, approved: 1, denied: 2, consumed: 3 }, validate: true

  attr_reader :plain_device_code

  before_validation :ensure_uuid
  before_validation :normalize_fields

  validates :uuid, :device_code_digest, :user_code_digest, :user_code_display, :client_name, :expires_at, presence: true
  validates :uuid, :device_code_digest, :user_code_digest, uniqueness: true
  validate :requested_scopes_are_supported

  scope :not_expired, -> { where("expires_at > ?", Time.current) }

  class << self
    def issue!(client_name:, requested_scopes: CliAccessToken::READ_SCOPES, expires_in: DEFAULT_EXPIRES_IN)
      device_code = SecureRandom.urlsafe_base64(48)
      user_code = unique_user_code

      create!(
        device_code_digest: digest(device_code),
        user_code_digest: digest(normalize_user_code(user_code)),
        user_code_display: user_code,
        client_name: client_name,
        requested_scopes: requested_scopes,
        expires_at: expires_in.from_now
      ).tap do |authorization|
        authorization.instance_variable_set(:@plain_device_code, device_code)
      end
    end

    def find_by_device_code(device_code)
      find_by(device_code_digest: digest(device_code))
    end

    def find_by_user_code(user_code)
      find_by(user_code_digest: digest(normalize_user_code(user_code)))
    end

    def digest(value)
      Digest::SHA256.hexdigest(value.to_s)
    end

    def normalize_user_code(value)
      value.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    end

    private

    def unique_user_code
      10.times do
        code = generated_user_code
        return code unless exists?(user_code_digest: digest(normalize_user_code(code)))
      end

      raise ActiveRecord::RecordNotUnique, "Could not generate a unique CLI device user code"
    end

    def generated_user_code
      chars = Array.new(8) { USER_CODE_ALPHABET.sample }.join
      "#{chars.first(4)}-#{chars.last(4)}"
    end
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def approve!(user:, all_projects:, allowed_project_ids:)
    with_lock do
      ensure_pending_and_current!

      selected_all_projects = ActiveModel::Type::Boolean.new.cast(all_projects) || false
      project_ids = normalize_project_ids(allowed_project_ids)
      validate_project_selection!(user, selected_all_projects, project_ids)

      update!(
        user: user,
        approved_all_projects: selected_all_projects,
        approved_project_ids: selected_all_projects ? [] : project_ids,
        status: :approved,
        approved_at: Time.current
      )
    end
  end

  def deny!
    with_lock do
      ensure_pending_and_current!
      update!(status: :denied, denied_at: Time.current)
    end
  end

  def exchange!
    with_lock do
      return ExchangeResult.new(status: :slow_down, access_token: nil) if pending? && polled_too_recently?

      touch_poll!

      return ExchangeResult.new(status: :expired_token, access_token: nil) if expired?
      return ExchangeResult.new(status: :access_denied, access_token: nil) if denied?
      return ExchangeResult.new(status: :authorization_pending, access_token: nil) if pending?
      return ExchangeResult.new(status: :invalid_grant, access_token: nil) if consumed? || cli_access_token.present?

      token = user.cli_access_tokens.create!(
        name: token_name,
        scopes: requested_scopes,
        all_projects: approved_all_projects?,
        allowed_project_ids: approved_project_ids,
        expires_at: CliAccessToken::DEFAULT_EXPIRES_IN.from_now
      )

      update!(cli_access_token: token, status: :consumed, consumed_at: Time.current)
      ExchangeResult.new(status: :authorized, access_token: token)
    end
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_fields
    self.client_name = client_name.to_s.strip.presence || "Logister CLI"
    self.requested_scopes = Array(requested_scopes).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    self.approved_project_ids = normalize_project_ids(approved_project_ids)
  end

  def requested_scopes_are_supported
    unknown = requested_scopes - CliAccessToken::READ_SCOPES
    errors.add(:requested_scopes, "contains unsupported CLI read scopes: #{unknown.join(', ')}") if unknown.any?
    errors.add(:requested_scopes, "must include at least one scope") if requested_scopes.empty?
  end

  def ensure_pending_and_current!
    raise ActiveRecord::RecordInvalid, self unless pending? && !expired?
  end

  def normalize_project_ids(ids)
    Array(ids).filter_map { |id| Integer(id, exception: false) }.uniq
  end

  def validate_project_selection!(user, all_projects, project_ids)
    return if all_projects

    if project_ids.empty?
      errors.add(:approved_project_ids, "must include at least one project")
      raise ActiveRecord::RecordInvalid, self
    end

    accessible_ids = user.accessible_projects.where(id: project_ids).pluck(:id)
    inaccessible_ids = project_ids - accessible_ids
    return if inaccessible_ids.empty?

    errors.add(:approved_project_ids, "contains inaccessible projects: #{inaccessible_ids.join(', ')}")
    raise ActiveRecord::RecordInvalid, self
  end

  def touch_poll!
    self.last_polled_at = Time.current
    save! if changed?
  end

  def polled_too_recently?
    last_polled_at.present? && last_polled_at > DEFAULT_INTERVAL_SECONDS.seconds.ago
  end

  def token_name
    "#{client_name} device login"
  end
end
