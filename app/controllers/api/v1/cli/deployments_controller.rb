# frozen_string_literal: true

class Api::V1::Cli::DeploymentsController < Api::V1::Cli::BaseController
  CURSOR_RESOURCE = "deployments"
  SEARCH_LIMIT = 200
  SORT_TIMESTAMP_SQL = "COALESCE(project_deployments.deployed_at, project_deployments.created_at)"

  before_action -> { require_cli_scopes!("deployments:read") }

  def index
    filters = normalized_filters
    cursor_filters = filters.except(:since, :until).merge(since: params[:since].to_s, until: params[:until].to_s)
    limit = cli_limit
    cursor = decode_cli_cursor(
      params[:cursor],
      resource: CURSOR_RESOURCE,
      project_uuid: cli_project.uuid,
      filters: cursor_filters
    )
    scope = filtered_scope(filters).includes(:project_source_repository, :github_repository)
    scope = scope.where("(#{SORT_TIMESTAMP_SQL}, project_deployments.uuid) < (?, ?::uuid)", cursor[:timestamp], cursor[:uuid]) if cursor
    records = scope.order(Arel.sql("#{SORT_TIMESTAMP_SQL} DESC"), uuid: :desc).limit(limit + 1).to_a
    has_more = records.length > limit
    records = records.first(limit)
    previous = ProjectDeploymentPreviousLookup.call(project: cli_project, deployments: records)
    next_cursor = if has_more && records.last
      encode_cli_cursor(
        resource: CURSOR_RESOURCE,
        project_uuid: cli_project.uuid,
        filters: cursor_filters,
        timestamp: deployment_timestamp(records.last),
        uuid: records.last.uuid
      )
    end

    render json: cli_list_payload(
      items: records.map { |deployment| Logister::CliSerializer.deployment(deployment, previous_deployment: previous[deployment.id]) },
      next_cursor:
    )
  end

  def show
    deployment = cli_project.deployments.includes(:project_source_repository, :github_repository).find_by!(uuid: params[:uuid])
    previous = ProjectDeploymentPreviousLookup.call(project: cli_project, deployments: [ deployment ])
    render json: Logister::CliSerializer.deployment(deployment, previous_deployment: previous[deployment.id])
  end

  private

  def normalized_filters
    since_at = Logister::CliQuery.relative_or_time(params[:since], parameter: "since")
    until_at = Logister::CliQuery.time(params[:until], parameter: "until")
    if since_at && until_at && since_at >= until_at
      raise Logister::CliQuery::InvalidParameter.new("since must be before until", parameter: "since")
    end

    {
      repository: Logister::CliQuery.text(params[:repository], parameter: "repository", max: 200),
      environment: Logister::CliQuery.text(params[:environment].presence || params[:env], parameter: "environment", max: 100),
      source: Logister::CliQuery.enum(params[:source], parameter: "source", allowed: ProjectDeployment::SOURCES.values),
      release: Logister::CliQuery.text(params[:release], parameter: "release", max: 200),
      q: Logister::CliQuery.text(params[:q].presence || params[:query], parameter: "q", max: SEARCH_LIMIT),
      since: since_at,
      until: until_at
    }.compact
  end

  def filtered_scope(filters)
    scope = cli_project.deployments
    scope = scope.where(repository_full_name: filters[:repository]) if filters[:repository].present?
    scope = scope.where(environment: filters[:environment]) if filters[:environment].present?
    scope = scope.where(source: filters[:source]) if filters[:source].present?
    scope = scope.where(release: filters[:release]) if filters[:release].present?
    scope = scope.where("#{SORT_TIMESTAMP_SQL} >= ?", filters[:since]) if filters[:since]
    scope = scope.where("#{SORT_TIMESTAMP_SQL} <= ?", filters[:until]) if filters[:until]
    scope = apply_text_filter(scope, filters[:q]) if filters[:q].present?
    scope
  end

  def apply_text_filter(scope, query)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    scope.where(
      <<~SQL.squish,
        LOWER(project_deployments.release) LIKE :term
        OR LOWER(project_deployments.commit_sha) LIKE :term
        OR LOWER(COALESCE(project_deployments.branch, '')) LIKE :term
        OR LOWER(project_deployments.repository_full_name) LIKE :term
      SQL
      term:
    )
  end

  def deployment_timestamp(deployment)
    deployment.deployed_at || deployment.created_at
  end
end
