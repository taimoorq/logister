# frozen_string_literal: true

require "uri"

module Github
  class IssueDeepLink
    def self.call(project:, group:, event: nil, source_excerpt: nil, repository: nil, logister_url: nil)
      new(
        project: project,
        group: group,
        event: event,
        source_excerpt: source_excerpt,
        repository: repository,
        logister_url: logister_url
      ).call
    end

    def initialize(project:, group:, event:, source_excerpt:, repository:, logister_url:)
      @project = project
      @group = group
      @event = event
      @source_excerpt = source_excerpt
      @repository = repository
      @logister_url = logister_url
    end

    def call
      source_repository = repository || default_repository
      return if source_repository.blank? || source_repository.full_name.blank?

      uri = URI.parse("#{Logister::GithubAppConfig.web_url}/#{source_repository.full_name}/issues/new")
      uri.query = URI.encode_www_form(title: title, body: body)
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    private

    attr_reader :project, :group, :event, :source_excerpt, :repository, :logister_url

    def default_repository
      project.source_repositories.github.enabled.order(:full_name).first
    end

    def title
      payload.title
    end

    def body
      payload.body
    end

    def payload
      @payload ||= IssuePayload.call(
        project: project,
        group: group,
        event: event,
        source_excerpt: source_excerpt,
        deployment_context: ProjectDeploymentContext.call(project: project, group: group, event: event),
        logister_url: logister_url
      )
    end
  end
end
