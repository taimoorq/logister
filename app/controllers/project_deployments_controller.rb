# frozen_string_literal: true

class ProjectDeploymentsController < ApplicationController
  include ProjectScope

  LIMIT = 100

  before_action :authenticate_user!
  before_action :set_accessible_project

  def index
    @deployment_filters = normalized_filters
    @deployment_repositories = @project.deployments.distinct.order(:repository_full_name).pluck(:repository_full_name).compact_blank
    @deployment_environments = @project.deployments.distinct.order(:environment).pluck(:environment).compact_blank
    @deployment_sources = ProjectDeployment::SOURCES.values
    @deployment_filters_active = deployment_filters_active?(@deployment_filters)
    @deployments_total = filtered_deployments.count
    @deployments = filtered_deployments
                   .includes(:project_source_repository, :github_repository)
                   .newest_first
                   .limit(LIMIT)
                   .to_a
    @previous_deployments_by_id = ProjectDeploymentPreviousLookup.call(project: @project, deployments: @deployments)

    render "project_deployments/index"
  end

  private

  def filtered_deployments
    filters = @deployment_filters
    scope = @project.deployments

    scope = scope.where(repository_full_name: filters[:repository]) if filters[:repository].present?
    scope = scope.where(environment: filters[:environment]) if filters[:environment].present?
    scope = scope.where(source: filters[:source]) if filters[:source].present?
    scope = apply_text_filter(scope, filters[:q]) if filters[:q].present?
    scope
  end

  def normalized_filters
    {
      repository: params[:repository].to_s.strip,
      environment: params[:environment].to_s.strip,
      source: params[:source].to_s.strip.presence_in(ProjectDeployment::SOURCES.values).to_s,
      q: params[:q].to_s.strip
    }
  end

  def deployment_filters_active?(filters)
    filters[:repository].present? ||
      filters[:environment].present? ||
      filters[:source].present? ||
      filters[:q].present?
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
      term: term
    )
  end
end
