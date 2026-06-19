# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Logister
  class DeploymentRecorder
    CONTENT_TYPE = "application/json"

    class << self
      def call(payload, configuration: Logister.configuration)
        return Logister.record_deployment(**payload) if Logister.respond_to?(:record_deployment)
        return false unless ready?(configuration)

        uri = deployment_uri(configuration)
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: configuration.timeout_seconds,
          read_timeout: configuration.timeout_seconds
        ) do |http|
          http.request(request(payload, configuration))
        end

        response.is_a?(Net::HTTPSuccess)
      rescue StandardError => error
        logger.warn("logister deployment record failed: #{error.class} #{error.message}")
        false
      end

      private

      def ready?(configuration)
        configuration&.enabled && configuration.api_key.to_s.present?
      end

      def request(payload, configuration)
        Net::HTTP::Post.new(deployment_uri(configuration)).tap do |request|
          request["Content-Type"] = CONTENT_TYPE
          request["Authorization"] = "Bearer #{configuration.api_key}"
          request.body = { deployment: payload }.to_json
        end
      end

      def deployment_uri(configuration)
        URI.parse(deployment_endpoint(configuration))
      end

      def deployment_endpoint(configuration)
        if configuration.respond_to?(:deployment_endpoint)
          configuration.deployment_endpoint
        else
          ENV["LOGISTER_DEPLOYMENT_ENDPOINT"].presence ||
            configuration.endpoint.to_s.sub(%r{/ingest_events\z}, "/deployments")
        end
      end

      def logger
        Logister.configuration.logger
      rescue StandardError
        Rails.logger
      end
    end
  end
end
