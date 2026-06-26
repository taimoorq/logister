# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "uri"

module Github
  class ContentsClient
    Result = Data.define(:content, :sha, :html_url)

    class Error < StandardError; end
    class NotConfigured < Error; end

    def initialize(token_provider: InstallationToken, config: Logister::GithubAppConfig)
      @token_provider = token_provider
      @config = config
    end

    def fetch(owner:, repo:, path:, ref:, installation:, repository_id: nil)
      raise NotConfigured, "GitHub App is not configured" unless config.configured?
      return nil unless installation&.available?

      token = token_provider.new(
        installation: installation,
        repository_ids: repository_id.present? ? [ repository_id ] : nil,
        permissions: { contents: "read", metadata: "read" },
        config: config
      ).token

      uri = contents_uri(owner: owner, repo: repo, path: path, ref: ref)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["Authorization"] = "Bearer #{token}"
      request["X-GitHub-Api-Version"] = config.api_version

      response = Logister::HttpClient.request(uri, request, open_timeout: 5, read_timeout: 5)
      return nil if response.is_a?(Net::HTTPNotFound)

      parsed = JSON.parse(response.body.presence || "{}")
      unless response.is_a?(Net::HTTPSuccess) && parsed["type"] == "file"
        raise Error, "GitHub contents request failed with #{response.code}"
      end

      Result.new(
        content: decode_content(parsed),
        sha: parsed["sha"],
        html_url: parsed["html_url"]
      )
    end

    private

    attr_reader :token_provider, :config

    def contents_uri(owner:, repo:, path:, ref:)
      encoded_path = path.to_s.split("/").map { |part| URI.encode_www_form_component(part) }.join("/")
      query = ref.present? ? "?#{URI.encode_www_form(ref: ref)}" : ""

      URI("#{config.api_url}/repos/#{owner}/#{repo}/contents/#{encoded_path}#{query}")
    end

    def decode_content(parsed)
      content = parsed["content"].to_s
      return content unless parsed["encoding"] == "base64"

      Base64.decode64(content)
    end
  end
end
