# frozen_string_literal: true

require "ipaddr"
require "uri"

module InstanceConfiguration
  # Validates values submitted from the installation settings form before they
  # are saved or tested. Saved secrets only travel to the destination they were
  # saved with, so a changed host, port, or endpoint needs the secret re-entered.
  class CandidateCheck
    CLICKHOUSE_PASSWORD_KEYS = %w[clickhouse.password clickhouse.migration_password].freeze
    DOMAIN_PATTERN = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/

    attr_reader :errors

    def self.call(section, values:, clear_keys: [], operation: :save)
      new(section, values: values, clear_keys: clear_keys, operation: operation).tap(&:validate)
    end

    def self.http_url?(value)
      uri = URI.parse(value.to_s.strip)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def initialize(section, values:, clear_keys: [], operation: :save)
      @section = Registry.section!(section).key
      @definitions = Registry.definitions_for(@section)
      @values = values
      @clear_keys = Array(clear_keys) & @definitions.map(&:key)
      @operation = operation
      @errors = []
    end

    def valid?
      errors.empty?
    end

    def validate
      validate_urls
      validate_secret_destinations
      validate_clickhouse_transport
      validate_registration_domains
      self
    end

    # Host the candidate configuration would connect to, recorded with test audits.
    def destination_host
      case @section
      when "email"
        candidate_values["email.smtp_address"].presence || "email-smtp.#{candidate_values['email.ses_region']}.amazonaws.com"
      when "clickhouse"
        host_for(candidate_values["clickhouse.url"])
      when "archive_storage"
        return unless candidate_values["archive_storage.service"] == "s3"

        host_for(candidate_values["archive_storage.endpoint"]) || "s3.#{candidate_values['archive_storage.region']}.amazonaws.com"
      when "github"
        host_for(candidate_values["github.api_url"])
      when "observability"
        host_for(candidate_values["observability.endpoint"])
      end
    end

    private

    def overrides
      @overrides ||= InstanceConfiguration.candidate_overrides(@section, @values).merge(
        @clear_keys.to_h { |key| [ key, Registry.definition!(key).default ] }
      )
    end

    def current_values
      @current_values ||= InstanceConfiguration.values_for(@section)
    end

    def candidate_values
      @candidate_values ||= InstanceConfiguration.values_for(@section, overrides: overrides)
    end

    def validate_urls
      @definitions.each do |definition|
        next unless definition.type == :url && @values.key?(definition.key)
        next if @clear_keys.include?(definition.key)

        value = @values.fetch(definition.key).to_s.strip
        next if value.blank? || self.class.http_url?(value)

        errors << "#{definition.label} must be an http:// or https:// URL with a host."
      end
    end

    def validate_secret_destinations
      @definitions.each do |secret|
        changed_keys = secret.destination_keys.reject { |key| current_values[key] == candidate_values[key] }
        next if changed_keys.empty?

        secret_entry = InstanceConfiguration.entry(secret.key, overrides: overrides)
        next if secret_entry.source == :candidate || secret_entry.effective_value.blank?

        changed_labels = changed_keys.map { |key| Registry.definition!(key).label }.to_sentence
        errors << if secret_entry.environment_override?
          "#{secret.label} is set by #{secret_entry.active_environment_key}, so change #{changed_labels} in the environment too."
        else
          "Re-enter #{secret.label} to use it with the changed #{changed_labels}. Saved secrets are only sent to the destination they were saved with."
        end
      end
    end

    # Plain HTTP would expose the password on the wire. The admin Test always
    # checks this; a save only checks it when the URL or a password changes,
    # so unrelated edits to an existing installation are not blocked.
    def validate_clickhouse_transport
      return unless @section == "clickhouse"
      return if InstanceConfiguration.entry("clickhouse.url", overrides: overrides).environment_override?
      return unless CLICKHOUSE_PASSWORD_KEYS.any? { |key| candidate_values[key].present? }
      return unless @operation == :test || clickhouse_transport_changed?

      uri = URI.parse(candidate_values["clickhouse.url"].to_s)
      return unless uri.scheme == "http" && !loopback_host?(uri.hostname)

      errors << "Use an https:// ClickHouse endpoint when a password is configured. Plain http:// is only allowed for a loopback host such as 127.0.0.1."
    rescue URI::InvalidURIError
      nil
    end

    def clickhouse_transport_changed?
      ([ "clickhouse.url" ] + CLICKHOUSE_PASSWORD_KEYS).any? { |key| current_values[key] != candidate_values[key] }
    end

    def validate_registration_domains
      return unless @section == "authentication"

      domains = RegistrationPolicy.parse_domains(candidate_values["authentication.registration_allowed_domains"])
      invalid = domains.grep_v(DOMAIN_PATTERN)
      errors << "Allowed sign-up domains contain invalid entries: #{invalid.first(5).join(', ')}." if invalid.any?
      return unless candidate_values["authentication.registration_mode"] == "allowed_domains" && domains.empty?

      errors << "Add at least one allowed sign-up domain, or choose another sign-up mode."
    end

    def host_for(value)
      URI.parse(value.to_s).host.presence if value.present?
    rescue URI::InvalidURIError
      nil
    end

    def loopback_host?(host)
      return false if host.blank?
      return true if host.casecmp?("localhost")

      IPAddr.new(host).loopback?
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
