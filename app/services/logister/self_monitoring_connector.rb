# frozen_string_literal: true

module Logister
  class SelfMonitoringConnector
    API_KEY_NAME = "Logister installation self-monitoring"
    Result = Struct.new(:status, :created_api_key, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(project:, actor:, installation: Installation.current)
      @project = project
      @actor = actor
      @installation = installation
    end

    def call
      validate_destination!

      current_status = SelfMonitoringStatus.new(project: project, installation: installation)
      return Result.new(status: current_status, created_api_key: false) if current_status.connected?

      created_api_key = false
      old_api_key = installation.self_monitoring_api_key
      api_key_entry = InstanceConfiguration.entry("observability.api_key")
      endpoint_entry = InstanceConfiguration.entry("observability.endpoint")
      settings = {}

      Installation.transaction do
        api_key = if api_key_entry.environment_override?
          ApiKey.authenticate(api_key_entry.effective_value)
        else
          created_api_key = true
          key = project.api_keys.create!(name: API_KEY_NAME, user: actor)
          settings["observability.api_key"] = key.plain_token
          key
        end

        settings["observability.endpoint"] = local_ingest_endpoint unless endpoint_entry.environment_override?

        installation.update!(
          self_monitoring_project: project,
          self_monitoring_api_key: api_key&.project_id == project.id ? api_key : nil
        )

        if settings.any?
          InstanceConfiguration.save_section!(
            "observability",
            values: settings,
            clear_keys: [],
            actor: actor
          )
        end

        if created_api_key && old_api_key && old_api_key.id != api_key.id && old_api_key.active?
          old_api_key.revoke!
        end

        InstanceConfiguration.audit!(
          key: "observability.self_monitoring_project",
          action: "connected",
          actor: actor,
          details: {
            "project_uuid" => project.uuid,
            "api_key_source" => api_key_entry.environment_override? ? "environment" : "generated",
            "endpoint_source" => endpoint_entry.environment_override? ? "environment" : "generated"
          }
        )
      end

      InstanceConfiguration::Runtime.apply!

      Result.new(
        status: SelfMonitoringStatus.new(project: project, installation: installation.reload),
        created_api_key: created_api_key
      )
    end

    private

    attr_reader :project, :actor, :installation

    def validate_destination!
      raise ArgumentError, "Self-monitoring requires an active Ruby project" unless project.integration_ruby? && !project.archived?
      raise ArgumentError, "An application administrator is required" unless application_administrator?
    end

    def local_ingest_endpoint
      SelfMonitoringStatus.new(project: project, installation: installation).local_ingest_endpoint
    end

    def application_administrator?
      return false unless actor
      return true if actor.application_admin?

      ENV.fetch("LOGISTER_ADMIN_EMAILS", "")
         .split(",")
         .map { |email| email.to_s.strip.downcase }
         .include?(actor.email.to_s.downcase)
    end
  end
end
