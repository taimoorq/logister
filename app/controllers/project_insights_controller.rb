# frozen_string_literal: true

require "digest"

class ProjectInsightsController < ApplicationController
  include ProjectScope

  INSIGHTS_SHELL_CACHE_TTL = 30.seconds
  INSIGHTS_DATA_CACHE_TTL = 10.seconds

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
        project_insights_cache_version,
        cache_time_bucket(INSIGHTS_SHELL_CACHE_TTL)
      ],
      expires_in: INSIGHTS_SHELL_CACHE_TTL
    ) do
      filter_options = ProjectInsights.filter_options(@project, window: window)

      {
        project_uuid: @project.uuid,
        endpoint: insights_data_project_path(@project),
        default_window: window,
        refresh_seconds: 30,
        windows: ProjectInsights.window_options,
        event_types: ProjectInsights.event_type_catalog,
        default_metrics: ProjectInsights.default_metric_keys,
        metric_catalog: ProjectInsights.catalog_for(@project, window: window),
        environments: filter_options.fetch(:environments),
        releases: filter_options.fetch(:releases),
        attributes: filter_options.fetch(:attributes)
      }
    end
  end

  def cached_insights_dashboard
    safe_cache_fetch(
      [
        "project",
        @project.id,
        "insights_data",
        ProjectInsights.normalize_window(params[:window]),
        project_insights_cache_version,
        cache_time_bucket(INSIGHTS_DATA_CACHE_TTL),
        Digest::SHA256.hexdigest(insights_cache_dimensions.to_json)
      ],
      expires_in: INSIGHTS_DATA_CACHE_TTL
    ) do
      ProjectInsights.dashboard_for(
        @project,
        window: params[:window],
        metrics: params[:metrics],
        environment: params[:environment],
        release: params[:release],
        attribute_filters: params[:attributes]
      )
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

  def project_insights_cache_version
    @project_insights_cache_version ||= @project.ingest_events.maximum(:updated_at)&.utc&.to_i || 0
  end
end
