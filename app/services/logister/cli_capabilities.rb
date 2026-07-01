# frozen_string_literal: true

require "digest"
require "yaml"

module Logister
  class CliCapabilities
    MINIMUM_CLI_VERSION = "0.1.0"
    RECOMMENDED_CLI_VERSION = "0.1.0"

    FEATURES = {
      capabilities: true,
      cli_access_tokens: true,
      device_authorization: true,
      projects: true,
      project_summary: true,
      events: true,
      logs: true,
      error_groups: true,
      traces: false,
      monitors: false,
      deployments: false,
      insights: false,
      metrics: false,
      ai_context_bundles: true,
      error_group_mutations: false
    }.freeze

    def self.call
      new.call
    end

    def call
      {
        server: "logister",
        server_version: server_version,
        api_contract_version: api_contract_version,
        api_contract_sha256: api_contract_sha256,
        minimum_cli_version: MINIMUM_CLI_VERSION,
        recommended_cli_version: RECOMMENDED_CLI_VERSION,
        generated_at: Time.current.utc.iso8601,
        endpoints: {
          capabilities: "/api/v1/cli/capabilities",
          device_authorizations: "/api/v1/cli/device_authorizations",
          device_token: "/api/v1/cli/device_authorizations/token"
        },
        auth: {
          cli_access_tokens: true,
          device_authorization: true,
          project_ingest_keys_for_read: false
        },
        features: FEATURES
      }
    end

    private

    def server_version
      configured = ENV["LOGISTER_RELEASE"].to_s.strip
      return configured.delete_prefix("v") if configured.match?(/\Av?[0-9]+(\.[0-9A-Za-z-]+)+\z/)

      changelog_version || api_contract_version
    end

    def changelog_version
      match = Rails.root.join("CHANGELOG.md").read.match(/^##\s+v?([0-9][^\s]*)\s+-\s+[0-9]{4}-[0-9]{2}-[0-9]{2}\s*$/)
      match&.[](1)
    end

    def api_contract_version
      openapi.fetch("info", {}).fetch("version", "unknown").to_s
    end

    def api_contract_sha256
      Digest::SHA256.file(openapi_path).hexdigest
    end

    def openapi
      @openapi ||= YAML.safe_load_file(openapi_path)
    end

    def openapi_path
      Rails.root.join("docs/openapi.yaml")
    end
  end
end
