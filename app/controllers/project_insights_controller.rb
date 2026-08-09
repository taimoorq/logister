# frozen_string_literal: true

class ProjectInsightsController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    window = ProjectInsights.normalize_window(params[:window])
    @insights_payload = cached_insights_shell_payload(window)

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
    window = ProjectInsights.normalize_window(params[:window])

    ProjectInsightsCache.dashboard(
      project: @project,
      window:,
      metrics: params[:metrics],
      environment: params[:environment],
      release: params[:release],
      attribute_filters: insights_attribute_filter_params
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
