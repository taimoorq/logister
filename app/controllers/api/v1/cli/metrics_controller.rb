# frozen_string_literal: true

class Api::V1::Cli::MetricsController < Api::V1::Cli::BaseController
  include Api::V1::Cli::InsightsParameters

  before_action -> { require_cli_scopes!("metrics:read") }

  def catalog
    window = cli_insights_window
    render json: cli_list_payload(items: ProjectInsightsCache.catalog(project: cli_project, window:))
  end

  def query
    window = cli_insights_window
    metrics = cli_metrics
    if metrics.length != 1
      raise Logister::CliQuery::InvalidParameter.new("metric query requires exactly one metric", parameter: "metric")
    end
    validate_cli_metrics!(project: cli_project, window:, metrics:, required: true)
    attributes = cli_insights_attributes
    validate_cli_insights_attributes!(project: cli_project, window:, attributes:)
    dashboard = ProjectInsightsCache.dashboard(
      project: cli_project,
      window:,
      metrics:,
      environment: Logister::CliQuery.text(params[:environment].presence || params[:env], parameter: "environment", max: ProjectInsights::MAX_FILTER_LENGTH),
      release: Logister::CliQuery.text(params[:release], parameter: "release", max: ProjectInsights::MAX_FILTER_LENGTH),
      attribute_filters: attributes
    )
    series = dashboard.fetch(:metric_series).find { |candidate| candidate.fetch(:key) == metrics.first }
    raise Logister::CliQuery::InvalidParameter.new("unknown metric", parameter: "metric") unless series

    render json: Logister::TelemetryRedactor.call(
      {
        metric: dashboard.fetch(:metric_catalog).find { |candidate| candidate.fetch(:key) == metrics.first },
        series:,
        window: dashboard.fetch(:window),
        bucket: dashboard.fetch(:bucket),
        filters: dashboard.fetch(:filters),
        generated_at: dashboard.fetch(:generated_at),
        analytics: safe_cli_analytics(dashboard[:analytics])
      }
    )
  end
end
