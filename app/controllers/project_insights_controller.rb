# frozen_string_literal: true

class ProjectInsightsController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    @telemetry_scope = ProjectTelemetryScope.from(project: @project, source: params)
    @insights_scope_projection = @telemetry_scope.project_for(:insights)
    @activity_scope_projection = @telemetry_scope.project_for(:activity)
    window = ProjectInsights.normalize_window(@insights_scope_projection.params[:window] || params[:window])
    @insights_payload = cached_insights_shell_payload(window).merge(
      scope_override: @telemetry_scope.to_h.any?,
      initial_environment: @insights_scope_projection.params[:environment],
      initial_release: @insights_scope_projection.params[:release],
      initial_attribute_filters: @insights_scope_projection.params[:attributes] || {}
    ).compact

    render "projects/insights"
  end

  def data
    render json: cached_insights_dashboard
  end

  private

  def cached_insights_shell_payload(window)
    ProjectInsightsCache.shell(project: @project, endpoint: insights_data_project_path(@project), window:)
  end

  def cached_insights_dashboard
    scope = ProjectTelemetryScope.from(project: @project, source: params).project_for(:insights)
    window = ProjectInsights.normalize_window(scope.params[:window] || params[:window])

    ProjectInsightsCache.dashboard(
      project: @project,
      window:,
      metrics: params[:metrics],
      environment: params[:environment].presence || scope.params[:environment],
      release: params[:release].presence || scope.params[:release],
      attribute_filters: (scope.params[:attributes] || {}).merge(insights_attribute_filter_params)
    )
  end

  def insights_attribute_filter_params
    raw = params[:attributes]
    filters =
      if raw.respond_to?(:to_unsafe_h)
        raw.to_unsafe_h
      elsif raw.respond_to?(:to_h)
        raw.to_h
      else
        {}
      end

    filters.transform_keys(&:to_s).sort.to_h
  end
end
