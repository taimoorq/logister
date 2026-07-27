# frozen_string_literal: true

require "uri"

module Logister
  class SelfMonitoringStatus
    attr_reader :installation, :project

    def initialize(project: nil, installation: Installation.current_if_available)
      @installation = installation
      @project = project || installation&.self_monitoring_project
    end

    def linked?
      installation.present? && project.present? && installation.self_monitoring_project_id == project.id
    end

    def connected?
      linked? && api_key_matches? && endpoint_matches?
    end

    def api_key_matches?
      effective_api_key&.project_id == project&.id && effective_api_key&.id == installation&.self_monitoring_api_key_id
    end

    def endpoint_matches?
      normalized_endpoint(endpoint_entry.effective_value) == normalized_endpoint(local_ingest_endpoint)
    end

    def environment_managed?
      api_key_entry.environment_override? || endpoint_entry.environment_override?
    end

    def environment_override_keys
      [ api_key_entry, endpoint_entry ].select(&:environment_override?).map(&:active_environment_key)
    end

    def local_ingest_endpoint
      "#{InstanceConfiguration.value('general.public_url').to_s.chomp('/')}/api/v1/ingest_events"
    end

    def issues
      return [ "Select a Ruby project for this installation." ] unless linked?

      problems = []
      problems << "The effective self-monitoring API key does not belong to this project." unless api_key_matches?
      problems << "The effective event endpoint does not point to this installation." unless endpoint_matches?
      problems
    end

    def api_key_entry
      @api_key_entry ||= InstanceConfiguration.entry("observability.api_key")
    end

    def endpoint_entry
      @endpoint_entry ||= InstanceConfiguration.entry("observability.endpoint")
    end

    def effective_api_key
      @effective_api_key ||= ApiKey.authenticate(api_key_entry.effective_value)
    end

    private

    def normalized_endpoint(value)
      uri = URI.parse(value.to_s)
      return nil unless uri.is_a?(URI::HTTP) && uri.host.present?

      default_port = uri.scheme == "https" ? 443 : 80
      port = uri.port == default_port ? nil : uri.port
      path = uri.path.to_s.sub(%r{/+\z}, "")
      [ uri.scheme.downcase, uri.host.downcase, port, path ]
    rescue URI::InvalidURIError
      nil
    end
  end
end
