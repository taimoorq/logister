# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Github
  class InstallationToken
    class Error < StandardError; end
    class NotConfigured < Error; end

    def initialize(installation:, repository_ids: nil, permissions: nil, config: Logister::GithubAppConfig, jwt_provider: AppJwt.new(config: config))
      @installation = installation
      @repository_ids = Array(repository_ids).compact_blank.map(&:to_i).presence
      @permissions = permissions&.compact_blank
      @config = config
      @jwt_provider = jwt_provider
    end

    def token
      Rails.cache.fetch(cache_key, expires_in: 50.minutes) do
        request_token
      end.fetch(:token)
    end

    private

    attr_reader :installation, :repository_ids, :permissions, :config, :jwt_provider

    def cache_key
      [
        "github_installation_token",
        installation.installation_id,
        repository_ids,
        permissions
      ]
    end

    def request_token
      raise NotConfigured, "GitHub App ID and private key are required" unless config.configured?
      raise Error, "GitHub installation is not available" unless installation&.available?

      uri = URI("#{config.api_url}/app/installations/#{installation.installation_id}/access_tokens")
      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["Authorization"] = "Bearer #{jwt_provider.token}"
      request["X-GitHub-Api-Version"] = config.api_version
      request.body = request_body.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 5) do |http|
        http.request(request)
      end

      parsed = JSON.parse(response.body.presence || "{}")
      unless response.is_a?(Net::HTTPSuccess) && parsed["token"].present?
        raise Error, "GitHub installation token request failed with #{response.code}"
      end

      {
        token: parsed.fetch("token"),
        expires_at: parsed["expires_at"]
      }
    end

    def request_body
      {}.tap do |body|
        body[:repository_ids] = repository_ids if repository_ids.present?
        body[:permissions] = permissions if permissions.present?
      end
    end
  end
end
