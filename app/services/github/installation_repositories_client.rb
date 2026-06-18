# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Github
  class InstallationRepositoriesClient
    class Error < StandardError; end
    class NotConfigured < Error; end

    def initialize(token_provider: InstallationToken, config: Logister::GithubAppConfig)
      @token_provider = token_provider
      @config = config
    end

    def list(installation:)
      raise NotConfigured, "GitHub App is not configured" unless config.configured?
      return [] unless installation&.available?

      token = token_provider.new(installation: installation, config: config).token
      repositories = []
      uri = URI("#{config.api_url}/installation/repositories?per_page=100")

      while uri
        response = request_page(uri, token)
        parsed = JSON.parse(response.body.presence || "{}")
        raise Error, "GitHub repositories request failed with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        repositories.concat(Array(parsed["repositories"]))
        uri = next_page_uri(response)
      end

      repositories
    end

    private

    attr_reader :token_provider, :config

    def request_page(uri, token)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["Authorization"] = "Bearer #{token}"
      request["X-GitHub-Api-Version"] = config.api_version

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 5) do |http|
        http.request(request)
      end
    end

    def next_page_uri(response)
      link_header = response["Link"].to_s
      next_link = link_header.split(",").find { |link| link.include?('rel="next"') }
      return if next_link.blank?

      match = next_link.match(/<([^>]+)>/)
      match ? URI(match[1]) : nil
    end
  end
end
