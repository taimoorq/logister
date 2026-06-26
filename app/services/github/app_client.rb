# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Github
  class AppClient
    class Error < StandardError; end
    class NotConfigured < Error; end

    def initialize(jwt_provider: AppJwt.new, config: Logister::GithubAppConfig)
      @jwt_provider = jwt_provider
      @config = config
    end

    def installation(installation_id)
      raise NotConfigured, "GitHub App is not configured" unless config.configured?

      uri = URI("#{config.api_url}/app/installations/#{installation_id}")
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["Authorization"] = "Bearer #{jwt_provider.token}"
      request["X-GitHub-Api-Version"] = config.api_version

      response = Logister::HttpClient.request(uri, request, open_timeout: 5, read_timeout: 5)

      parsed = JSON.parse(response.body.presence || "{}")
      return parsed if response.is_a?(Net::HTTPSuccess)

      raise Error, "GitHub installation lookup failed with #{response.code}"
    end

    private

    attr_reader :jwt_provider, :config
  end
end
