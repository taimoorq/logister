# frozen_string_literal: true

class ProjectDeploymentPreviousLookup
  def self.call(project:, deployments:)
    new(project: project, deployments: deployments).call
  end

  def initialize(project:, deployments:)
    @project = project
    @deployment_ids = deployments.map(&:id).compact.uniq
  end

  def call
    return {} if @deployment_ids.empty?

    requested = @project.deployments.where(id: @deployment_ids)
      .select(:id, :repository_full_name, :environment, Arel.sql("COALESCE(deployed_at, created_at) AS cutoff"))
    previous = @project.deployments
      .where("project_deployments.repository_full_name = requested.repository_full_name")
      .where("project_deployments.environment = requested.environment")
    dated = previous.where.not(deployed_at: nil)
      .where("COALESCE(project_deployments.deployed_at, project_deployments.updated_at) < requested.cutoff")
      .newest_first.limit(1)
    undated = previous.where(deployed_at: nil).where("project_deployments.created_at < requested.cutoff")
      .newest_first.limit(1)

    # Each visible deployment retrieves at most one predecessor, preserving the
    # existing updated_at fallback order for deployments without deployed_at.
    ProjectDeployment.find_by_sql(<<~SQL).to_h { |row| [ row.requested_deployment_id, row ] }
      SELECT previous.*, requested.id AS requested_deployment_id
      FROM (#{requested.to_sql}) requested
      CROSS JOIN LATERAL (
        SELECT candidates.* FROM ((#{dated.to_sql}) UNION ALL (#{undated.to_sql})) candidates
        ORDER BY COALESCE(candidates.deployed_at, candidates.updated_at) DESC, candidates.id DESC
        LIMIT 1
      ) previous
    SQL
  end
end
