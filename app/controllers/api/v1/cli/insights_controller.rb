# frozen_string_literal: true

class Api::V1::Cli::InsightsController < Api::V1::Cli::BaseController
  include Api::V1::Cli::InsightsParameters

  before_action -> { require_cli_scopes!("insights:read") }

  def show
    window = cli_insights_window
    metrics = cli_metrics
    attributes = cli_insights_attributes
    validate_cli_metrics!(project: cli_project, window:, metrics:) if metrics.any?
    validate_cli_insights_attributes!(project: cli_project, window:, attributes:)
    dashboard = ProjectInsightsCache.dashboard(
      project: cli_project,
      window:,
      metrics: metrics.presence || ProjectInsights.default_metric_keys,
      environment: Logister::CliQuery.text(params[:environment].presence || params[:env], parameter: "environment", max: ProjectInsights::MAX_FILTER_LENGTH),
      release: Logister::CliQuery.text(params[:release], parameter: "release", max: ProjectInsights::MAX_FILTER_LENGTH),
      attribute_filters: attributes
    )
    payload = dashboard.except(:recent_events)
    payload[:analytics] = safe_cli_analytics(payload[:analytics])

    render json: Logister::TelemetryRedactor.call(payload)
  end
end
