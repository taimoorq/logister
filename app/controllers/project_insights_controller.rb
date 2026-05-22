# frozen_string_literal: true

class ProjectInsightsController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    window = ProjectInsights.normalize_window(params[:window])
    filter_options = ProjectInsights.filter_options(@project, window: window)

    @insights_payload = {
      project_uuid: @project.uuid,
      endpoint: insights_data_project_path(@project),
      default_window: window,
      refresh_seconds: 30,
      windows: ProjectInsights.window_options,
      event_types: ProjectInsights.event_type_catalog,
      default_metrics: ProjectInsights.default_metric_keys,
      metric_catalog: ProjectInsights.catalog_for(@project, window: window),
      environments: filter_options.fetch(:environments),
      releases: filter_options.fetch(:releases)
    }

    render "projects/insights"
  end

  def data
    render json: ProjectInsights.dashboard_for(
      @project,
      window: params[:window],
      metrics: params[:metrics],
      environment: params[:environment],
      release: params[:release]
    )
  end
end
