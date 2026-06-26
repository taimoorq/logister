# frozen_string_literal: true

class ProjectDeploymentPreviousLookup
  def self.call(project:, deployments:)
    new(project: project, deployments: deployments).call
  end

  def initialize(project:, deployments:)
    @project = project
    @deployments = deployments.to_a
  end

  def call
    return {} if searchable_deployments.empty?

    candidates_by_key = previous_candidates.group_by { |deployment| deployment_key(deployment) }

    searchable_deployments.each_with_object({}) do |deployment, previous_by_id|
      previous = candidates_by_key.fetch(deployment_key(deployment), []).find do |candidate|
        deployment_timestamp(candidate) < deployment_timestamp(deployment)
      end
      previous_by_id[deployment.id] = previous if previous
    end
  end

  private

  attr_reader :project, :deployments

  def searchable_deployments
    @searchable_deployments ||= deployments.select { |deployment| deployment_timestamp(deployment).present? }
  end

  def previous_candidates
    project.deployments
           .where(repository_full_name: repositories, environment: environments)
           .where("COALESCE(deployed_at, created_at) < ?", latest_timestamp)
           .newest_first
           .to_a
  end

  def repositories
    searchable_deployments.map(&:repository_full_name).compact_blank.uniq
  end

  def environments
    searchable_deployments.map(&:environment).compact_blank.uniq
  end

  def latest_timestamp
    searchable_deployments.map { |deployment| deployment_timestamp(deployment) }.max
  end

  def deployment_key(deployment)
    [ deployment.repository_full_name, deployment.environment ]
  end

  def deployment_timestamp(deployment)
    deployment.deployed_at || deployment.created_at
  end
end
