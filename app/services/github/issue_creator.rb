# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Github
  class IssueCreator
    Result = Data.define(:html_url, :number, :title, :body, :repository_full_name)

    class Error < StandardError; end
    class PermissionError < Error; end
    class NotConfigured < Error; end

    def self.call(project:, group:, event: nil, source_excerpt: nil, repository: nil, logister_url: nil, token_provider: InstallationToken, config: Logister::GithubAppConfig)
      new(token_provider: token_provider, config: config).call(
        project: project,
        group: group,
        event: event,
        source_excerpt: source_excerpt,
        repository: repository,
        logister_url: logister_url
      )
    end

    def initialize(token_provider: InstallationToken, config: Logister::GithubAppConfig)
      @token_provider = token_provider
      @config = config
    end

    def call(project:, group:, event:, source_excerpt:, repository:, logister_url:)
      raise NotConfigured, "GitHub App is not configured" unless config.configured?

      source_repository = repository || default_repository(project)
      raise Error, "No GitHub source repository is available for this project." if source_repository.blank?
      raise PermissionError, "GitHub App installation needs Issues write permission." unless source_repository.github_issue_creation_available?

      deployment_context = ProjectDeploymentContext.call(project: project, group: group, event: event)
      payload = IssuePayload.call(
        project: project,
        group: group,
        event: event,
        source_excerpt: source_excerpt,
        deployment_context: deployment_context,
        logister_url: logister_url
      )

      token = installation_token(source_repository)
      parsed = create_issue(source_repository, payload, token)

      Result.new(
        html_url: parsed.fetch("html_url"),
        number: parsed["number"],
        title: parsed["title"].presence || payload.title,
        body: payload.body,
        repository_full_name: source_repository.full_name
      )
    end

    private

    attr_reader :token_provider, :config

    def default_repository(project)
      project.source_repositories.github.enabled.includes(:github_installation, github_repository: :github_installation).find(&:github_issue_creation_available?)
    end

    def installation_token(source_repository)
      token_provider.new(
        installation: source_repository.effective_github_installation,
        repository_ids: source_repository.github_repository&.external_id || source_repository.external_id,
        permissions: { issues: "write", metadata: "read" },
        config: config
      ).token
    end

    def create_issue(source_repository, payload, token)
      uri = URI("#{config.api_url}/repos/#{source_repository.owner_name}/#{source_repository.repo_name}/issues")
      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["Authorization"] = "Bearer #{token}"
      request["X-GitHub-Api-Version"] = config.api_version
      request.body = { title: payload.title, body: payload.body }.to_json

      response = Logister::HttpClient.request(uri, request, open_timeout: 5, read_timeout: 5)
      parsed = JSON.parse(response.body.presence || "{}")

      return parsed if response.is_a?(Net::HTTPCreated) && parsed["html_url"].present?

      raise PermissionError, "GitHub rejected issue creation for this installation." if response.is_a?(Net::HTTPForbidden) || response.is_a?(Net::HTTPNotFound)

      raise Error, "GitHub issue creation failed with #{response.code}"
    end
  end
end
