# frozen_string_literal: true

class ProjectDeploymentIndexer
  Result = Data.define(:deployment, :indexed, :errors) do
    def indexed?
      indexed
    end
  end

  COMMIT_SHA_PATHS = [
    [ "commit_sha" ],
    [ "commitSha" ],
    [ "git_sha" ],
    [ "gitSha" ],
    [ "sha" ],
    [ "git", "sha" ],
    [ "git", "commit_sha" ],
    [ "github", "sha" ],
    [ "github", "commit_sha" ],
    [ "deployment", "commit_sha" ]
  ].freeze

  REPOSITORY_PATHS = [
    [ "repository" ],
    [ "repo" ],
    [ "github_repository" ],
    [ "githubRepository" ],
    [ "github", "repository" ],
    [ "github", "repo" ],
    [ "git", "repository" ],
    [ "deployment", "repository" ]
  ].freeze

  BRANCH_PATHS = [
    [ "branch" ],
    [ "git", "branch" ],
    [ "github", "branch" ],
    [ "deployment", "branch" ],
    [ "ref" ],
    [ "github", "ref" ]
  ].freeze

  RELEASE_PATHS = [
    [ "release" ],
    [ "deployment", "release" ]
  ].freeze

  ENVIRONMENT_PATHS = [
    [ "environment" ],
    [ "deployment", "environment" ]
  ].freeze

  DEPLOYED_AT_PATHS = [
    [ "deployed_at" ],
    [ "deployedAt" ],
    [ "deployment", "deployed_at" ],
    [ "deployment", "deployedAt" ]
  ].freeze

  PULL_REQUEST_NUMBER_PATHS = [
    [ "pull_request_number" ],
    [ "pullRequestNumber" ],
    [ "pull_request", "number" ],
    [ "pullRequest", "number" ],
    [ "github", "pull_request", "number" ],
    [ "github", "pullRequest", "number" ],
    [ "github", "event", "pull_request", "number" ],
    [ "deployment", "pull_request_number" ]
  ].freeze

  PULL_REQUEST_URL_PATHS = [
    [ "pull_request_url" ],
    [ "pullRequestUrl" ],
    [ "pull_request", "html_url" ],
    [ "pullRequest", "html_url" ],
    [ "github", "pull_request", "html_url" ],
    [ "github", "event", "pull_request", "html_url" ],
    [ "deployment", "pull_request_url" ]
  ].freeze

  RELEASE_URL_PATHS = [
    [ "release_url" ],
    [ "releaseUrl" ],
    [ "github_release_url" ],
    [ "githubReleaseUrl" ],
    [ "github", "release", "html_url" ],
    [ "github", "event", "release", "html_url" ],
    [ "deployment", "release_url" ]
  ].freeze

  RELEASE_TAG_PATHS = [
    [ "release_tag" ],
    [ "releaseTag" ],
    [ "tag" ],
    [ "tag_name" ],
    [ "tagName" ],
    [ "github", "release", "tag_name" ],
    [ "github", "event", "release", "tag_name" ],
    [ "deployment", "release_tag" ]
  ].freeze

  URL_METADATA_PATHS = {
    "compare_url" => [
      [ "compare_url" ],
      [ "compareUrl" ],
      [ "github", "compare_url" ],
      [ "deployment", "compare_url" ]
    ],
    "workflow_run_url" => [
      [ "workflow_run_url" ],
      [ "workflowRunUrl" ],
      [ "github", "workflow_run_url" ],
      [ "deployment", "workflow_run_url" ]
    ],
    "deployment_url" => [
      [ "deployment_url" ],
      [ "deploymentUrl" ],
      [ "github", "deployment_url" ],
      [ "deployment", "url" ]
    ]
  }.freeze

  def self.from_event(event)
    new(
      project: event.project,
      payload: event_payload(event),
      source: ProjectDeployment::SOURCES[:telemetry],
      required: false,
      metadata: {
        "event_id" => event.id,
        "event_uuid" => event.uuid
      }.compact
    ).index
  rescue StandardError => error
    Rails.logger.info("deployment indexing skipped for event #{event&.id}: #{error.class} #{error.message}")
    noop
  end

  def self.from_payload(project:, payload:, source: ProjectDeployment::SOURCES[:api])
    new(project: project, payload: payload, source: source, required: true).index
  end

  def self.noop(errors = [])
    Result.new(deployment: nil, indexed: false, errors: errors)
  end

  def self.event_payload(event)
    context = event.context.is_a?(Hash) ? event.context.deep_dup : {}
    context["release"] ||= IngestEvent.release(event)
    context["environment"] ||= IngestEvent.environment(event)
    context["deployed_at"] ||= event.occurred_at
    context
  end
  private_class_method :event_payload

  def initialize(project:, payload:, source:, required:, metadata: {})
    @project = project
    @payload = normalize_hash(payload)
    @source = source
    @required = required
    @metadata = metadata
  end

  def index
    attrs = deployment_attributes
    errors = required_errors(attrs)
    return Result.new(deployment: nil, indexed: false, errors: errors) if errors.any?
    return Result.new(deployment: nil, indexed: false, errors: []) unless indexable?(attrs)

    deployment = ProjectDeployment.find_or_initialize_by(
      project: project,
      repository_full_name: attrs[:repository_full_name],
      environment: attrs[:environment],
      release: attrs[:release]
    )
    deployment.assign_attributes(attrs.except(:repository_full_name, :environment, :release).merge(
      source: source,
      metadata: (deployment.metadata || {}).merge(deployment_metadata(attrs[:repository_full_name])).compact
    ))

    if deployment.save
      Result.new(deployment: deployment, indexed: true, errors: [])
    else
      Result.new(deployment: deployment, indexed: false, errors: deployment.errors.full_messages)
    end
  end

  private

  attr_reader :project, :payload, :source, :required, :metadata

  def deployment_attributes
    repository_full_name, source_repository = repository_identity

    {
      provider: ProjectDeployment::PROVIDERS[:github],
      project_source_repository: source_repository,
      github_repository: source_repository&.github_repository,
      repository_full_name: repository_full_name,
      environment: environment,
      release: release,
      commit_sha: commit_sha,
      branch: branch,
      deployed_at: deployed_at
    }
  end

  def repository_identity
    hinted_full_name = ProjectDeployment.normalize_repository_full_name(first_value(REPOSITORY_PATHS))
    source_repository = source_repository_for(hinted_full_name)
    fallback_repository = hinted_full_name.blank? ? sole_source_repository : nil

    [
      hinted_full_name || fallback_repository&.full_name,
      source_repository || fallback_repository
    ]
  end

  def source_repository_for(full_name)
    return if full_name.blank?

    project.source_repositories.github.enabled.find { |repository| repository.full_name.casecmp?(full_name) }
  end

  def sole_source_repository
    repositories = project.source_repositories.github.enabled.to_a
    repositories.one? ? repositories.first : nil
  end

  def environment
    ProjectDeployment.normalize_environment(first_value(ENVIRONMENT_PATHS))
  end

  def release
    first_value(RELEASE_PATHS).to_s.strip.presence
  end

  def commit_sha
    value = first_value(COMMIT_SHA_PATHS).to_s.strip.downcase
    value.match?(ProjectDeployment::SHA_PATTERN) ? value : value.presence
  end

  def branch
    first_value(BRANCH_PATHS).to_s.strip.delete_prefix("refs/heads/").presence
  end

  def deployed_at
    parse_time(first_value(DEPLOYED_AT_PATHS)) || Time.current
  end

  def deployment_metadata(repository_full_name)
    metadata.merge(github_metadata(repository_full_name)).compact
  end

  def github_metadata(repository_full_name)
    {}.tap do |values|
      values["pull_request_number"] = pull_request_number
      values["pull_request_url"] = first_value(PULL_REQUEST_URL_PATHS).to_s.strip.presence || inferred_pull_request_url(repository_full_name, values["pull_request_number"])
      values["release_tag"] = first_value(RELEASE_TAG_PATHS).to_s.strip.presence
      values["release_url"] = first_value(RELEASE_URL_PATHS).to_s.strip.presence || inferred_release_url(repository_full_name, values["release_tag"])
      URL_METADATA_PATHS.each do |key, paths|
        values[key] = first_value(paths).to_s.strip.presence
      end
    end
  end

  def pull_request_number
    explicit = first_value(PULL_REQUEST_NUMBER_PATHS).to_s.strip.presence
    return explicit if explicit.present?

    first_value(BRANCH_PATHS).to_s.match(%r{\Arefs/pull/(\d+)/})&.[](1)
  end

  def inferred_pull_request_url(repository_full_name, number)
    return if repository_full_name.blank? || number.blank?

    "#{Logister::GithubAppConfig.web_url}/#{repository_full_name}/pull/#{number}"
  end

  def inferred_release_url(repository_full_name, tag)
    return if repository_full_name.blank? || tag.blank?

    "#{Logister::GithubAppConfig.web_url}/#{repository_full_name}/releases/tag/#{ERB::Util.url_encode(tag)}"
  end

  def required_errors(attrs)
    return [] unless required

    [].tap do |errors|
      errors << "Release can't be blank" if attrs[:release].blank?
      errors << "Repository can't be blank" if attrs[:repository_full_name].blank?
      errors << "Commit sha can't be blank" if attrs[:commit_sha].blank?
      errors << "Commit sha must be a 7 to 40 character commit SHA" if attrs[:commit_sha].present? && !ProjectDeployment.valid_commit_sha?(attrs[:commit_sha])
    end
  end

  def indexable?(attrs)
    attrs[:release].present? &&
      attrs[:repository_full_name].present? &&
      attrs[:commit_sha].present? &&
      ProjectDeployment.valid_commit_sha?(attrs[:commit_sha])
  end

  def first_value(paths)
    paths.lazy.map { |path| dig_value(payload, path) }.find(&:present?)
  end

  def dig_value(value, path)
    path.reduce(value) do |current, key|
      return nil unless current.is_a?(Hash)

      current[key] || current[key.to_sym]
    end
  end

  def normalize_hash(value)
    hash =
      if value.respond_to?(:to_unsafe_h)
        value.to_unsafe_h
      elsif value.respond_to?(:to_h)
        value.to_h
      else
        {}
      end

    hash.deep_stringify_keys
  end

  def parse_time(value)
    return value if value.is_a?(Time)
    return value.to_time if value.respond_to?(:to_time) && !value.is_a?(String)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
