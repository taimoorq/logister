# frozen_string_literal: true

require "digest"

class ProjectInsightsController < ApplicationController
  include ProjectScope

  INSIGHTS_SHELL_CACHE_TTL = 1.minute
  INSIGHTS_CATALOG_CACHE_TTL = 1.minute
  INSIGHTS_FILTER_OPTIONS_CACHE_TTL = 1.minute
  INSIGHTS_DATA_CACHE_TTL = 30.seconds

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
    safe_cache_fetch(
      [
        "project",
        @project.id,
        "insights_shell",
        window,
        cache_time_bucket(INSIGHTS_SHELL_CACHE_TTL)
      ],
      expires_in: INSIGHTS_SHELL_CACHE_TTL
    ) do
      ProjectInsights.shell_payload(@project, endpoint: insights_data_project_path(@project), window: window)
    end
  end

  def cached_insights_dashboard
    window = ProjectInsights.normalize_window(params[:window])

    safe_cache_fetch(
      [
        "project",
        @project.id,
        "insights_data",
        window,
        cache_time_bucket(INSIGHTS_DATA_CACHE_TTL),
        Digest::SHA256.hexdigest(insights_cache_dimensions.to_json)
      ],
      expires_in: INSIGHTS_DATA_CACHE_TTL
    ) do
      ProjectInsights.dashboard_for(
        @project,
        window: window,
        metrics: params[:metrics],
        environment: params[:environment],
        release: params[:release],
        attribute_filters: params[:attributes],
        catalog: cached_insights_catalog(window),
        filter_options: cached_insights_filter_options(window)
      )
    end
  end

  def cached_insights_catalog(window)
    safe_cache_fetch(
      [
        "project",
        @project.id,
        "insights_catalog",
        window,
        cache_time_bucket(INSIGHTS_CATALOG_CACHE_TTL)
      ],
      expires_in: INSIGHTS_CATALOG_CACHE_TTL
    ) do
      ProjectInsights.catalog_for(@project, window: window)
    end
  end

  def cached_insights_filter_options(window)
    safe_cache_fetch(
      [
        "project",
        @project.id,
        "insights_filter_options",
        window,
        cache_time_bucket(INSIGHTS_FILTER_OPTIONS_CACHE_TTL)
      ],
      expires_in: INSIGHTS_FILTER_OPTIONS_CACHE_TTL
    ) do
      ProjectInsights.filter_options(@project, window: window)
    end
  end

  def insights_cache_dimensions
    {
      metrics: Array(params[:metrics]).map(&:to_s),
      environment: params[:environment].to_s,
      release: params[:release].to_s,
      attributes: insights_attribute_filter_params
    }
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
