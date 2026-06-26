# frozen_string_literal: true

class MobileIngestTokenValidator
  def self.call(token)
    new(token).call
  end

  def initialize(token)
    @token = token
  end

  def call
    validate_project_active
    validate_api_key_project
    validate_api_key_active
    validate_project_platform
    validate_expiration_window if token.new_record?
    validate_allowed_event_types
  end

  private

  attr_reader :token

  def validate_project_active
    token.errors.add(:project, "is archived") if token.project&.archived?
  end

  def validate_api_key_project
    return if token.api_key.blank? || token.project.blank?
    return if token.api_key.project_id == token.project.id

    token.errors.add(:api_key, "must belong to the same project")
  end

  def validate_api_key_active
    return if token.api_key.blank? || token.api_key.active?

    token.errors.add(:api_key, "is revoked")
  end

  def validate_project_platform
    return if token.project.blank? || token.platform.blank?
    return if token.project.integration_kind == token.platform

    token.errors.add(:platform, "must match the project integration kind")
  end

  def validate_expiration_window
    return if token.expires_at.blank?

    seconds_from_now = token.expires_at - Time.current
    if seconds_from_now < MobileIngestToken::MIN_EXPIRES_IN_SECONDS - 1
      token.errors.add(:expires_at, "must be at least #{MobileIngestToken::MIN_EXPIRES_IN_SECONDS} seconds from now")
    elsif seconds_from_now > MobileIngestToken::MAX_EXPIRES_IN_SECONDS + 1
      token.errors.add(:expires_at, "must be within #{MobileIngestToken::MAX_EXPIRES_IN_SECONDS} seconds")
    end
  end

  def validate_allowed_event_types
    unknown = token.allowed_event_types - MobileIngestToken::DEFAULT_ALLOWED_EVENT_TYPES
    return if unknown.empty?

    token.errors.add(:allowed_event_types, "contains unsupported values: #{unknown.join(', ')}")
  end
end
