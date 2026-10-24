# frozen_string_literal: true

# Project integrations name an environment variable that holds their provider
# credential. Project managers choose the name, so only operator-approved
# variables may be read: names with the LOGISTER_INTEGRATION_ prefix, or names
# the operator lists in LOGISTER_INTEGRATION_CREDENTIAL_ENV_ALLOWLIST.
module IntegrationCredentialReference
  PREFIX = "LOGISTER_INTEGRATION_"
  ALLOWLIST_ENV = "LOGISTER_INTEGRATION_CREDENTIAL_ENV_ALLOWLIST"
  NAME_PATTERN = /\A[A-Z][A-Z0-9_]*\z/

  # Messages are deliberately generic: they are stored on the setting and shown
  # to project managers, so they must not reveal whether or what a variable holds.
  class Error < StandardError
    MESSAGES = {
      not_allowed: "Credential reference is not an allowed environment variable.",
      not_configured: "Credential is not configured.",
      unparseable: "Credential could not be parsed.",
      rejected: "Credential was rejected by the provider."
    }.freeze

    attr_reader :category

    def initialize(category)
      @category = category
      super(MESSAGES.fetch(category))
    end
  end

  module_function

  def allowed?(name)
    name = name.to_s
    return false unless name.match?(NAME_PATTERN)
    return false if name == ALLOWLIST_ENV

    name.start_with?(PREFIX) || allowlist.include?(name)
  end

  def fetch!(name)
    raise Error.new(:not_allowed) unless allowed?(name)

    ENV[name.to_s].to_s.strip.presence || raise(Error.new(:not_configured))
  end

  def allowlist
    ENV[ALLOWLIST_ENV].to_s.split(",").map(&:strip).compact_blank
  end

  def requirement_message
    "must name an environment variable that starts with #{PREFIX} or is listed in #{ALLOWLIST_ENV}"
  end
end
