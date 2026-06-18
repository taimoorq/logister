# frozen_string_literal: true

class ProjectDeploymentContext
  Result = Data.define(:deployment, :previous_deployment, :started_after, :minutes_after, :exact_release) do
    def present?
      deployment.present?
    end

    def exact_release?
      exact_release
    end
  end

  def self.call(project:, group:, event: nil)
    new(project: project, group: group, event: event).call
  end

  def initialize(project:, group:, event:)
    @project = project
    @group = group
    @event = event
  end

  def call
    deployment = exact_release_deployment || deployment_before_first_seen
    return Result.new(deployment: nil, previous_deployment: nil, started_after: false, minutes_after: nil, exact_release: false) if deployment.blank?

    Result.new(
      deployment: deployment,
      previous_deployment: previous_deployment_for(deployment),
      started_after: first_seen_at.present? && deployment.deployed_at.present? && deployment.deployed_at <= first_seen_at,
      minutes_after: minutes_after(deployment),
      exact_release: deployment.release == release_hint
    )
  end

  private

  attr_reader :project, :group, :event

  def exact_release_deployment
    return if release_hint.blank?

    relation.find_by(release: release_hint)
  end

  def deployment_before_first_seen
    return if first_seen_at.blank?

    relation.where("COALESCE(deployed_at, created_at) <= ?", first_seen_at).newest_first.first
  end

  def previous_deployment_for(deployment)
    timestamp = deployment.deployed_at || deployment.created_at
    return if timestamp.blank?

    project.deployments
           .where(repository_full_name: deployment.repository_full_name, environment: deployment.environment)
           .where("COALESCE(deployed_at, created_at) < ?", timestamp)
           .newest_first
           .first
  end

  def relation
    scope = project.deployments
    scope = scope.where(environment: environment_hint) if environment_hint.present?
    scope = scope.where(repository_full_name: repository_hint) if repository_hint.present?
    scope
  end

  def first_seen_at
    @first_seen_at ||= group&.first_seen_at || event&.occurred_at
  end

  def minutes_after(deployment)
    return if first_seen_at.blank? || deployment.deployed_at.blank? || deployment.deployed_at > first_seen_at

    ((first_seen_at - deployment.deployed_at) / 60.0).round
  end

  def release_hint
    @release_hint ||= group&.introduced_in_release.presence ||
      (event ? IngestEvent.release(event).presence : nil) ||
      group&.last_seen_release.presence
  end

  def environment_hint
    @environment_hint ||= group&.stage.presence || (event ? IngestEvent.environment(event) : nil)
  end

  def repository_hint
    @repository_hint ||= ProjectDeployment.normalize_repository_full_name(first_context_value(
      [ "repository" ],
      [ "repo" ],
      [ "github_repository" ],
      [ "githubRepository" ],
      [ "github", "repository" ],
      [ "github", "repo" ],
      [ "git", "repository" ],
      [ "deployment", "repository" ]
    ))
  end

  def first_context_value(*paths)
    paths.each do |path|
      value = dig_context(context_hash, path)
      return value if value.present?
    end

    nil
  end

  def context_hash
    @context_hash ||= event&.context.is_a?(Hash) ? event.context : {}
  end

  def dig_context(hash, path)
    current = hash
    path.each do |segment|
      return nil unless current.is_a?(Hash)

      current = current[segment] || current[segment.to_sym]
    end
    current
  end
end
