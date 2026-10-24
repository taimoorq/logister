# frozen_string_literal: true

# Instance-wide public sign-up policy from `authentication.registration_mode`.
# First-administrator setup is handled by InstanceSetupController and is never
# blocked by this policy.
class RegistrationPolicy
  MODES = %w[open allowed_domains closed].freeze

  attr_reader :mode, :allowed_domains

  def self.current
    new(
      mode: InstanceConfiguration.value("authentication.registration_mode"),
      allowed_domains: InstanceConfiguration.value("authentication.registration_allowed_domains")
    )
  end

  def self.parse_domains(value)
    value.to_s.split(/[\s,]+/).map { |domain| domain.strip.downcase.delete_prefix("@") }.compact_blank.uniq
  end

  def initialize(mode:, allowed_domains: nil)
    @mode = mode.to_s.presence_in(MODES) || "open"
    @allowed_domains = self.class.parse_domains(allowed_domains)
  end

  def open?
    mode == "open"
  end

  def allowed_domains?
    mode == "allowed_domains"
  end

  # True when the public sign-up page should be offered at all.
  def sign_up_available?
    open? || (allowed_domains? && allowed_domains.any?)
  end

  def permits_email?(email)
    return true if open?
    return false unless sign_up_available?

    local, domain, extra = email.to_s.strip.downcase.split("@", 3)
    return false if local.blank? || domain.blank? || !extra.nil?

    allowed_domains.include?(domain)
  end
end
