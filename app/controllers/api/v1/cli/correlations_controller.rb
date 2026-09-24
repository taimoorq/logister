class Api::V1::Cli::CorrelationsController < Api::V1::Cli::BaseController
  before_action -> { require_cli_scopes!("events:read", "errors:read", "traces:read", "deployments:read") }

  def show
    event = cli_project.ingest_events.find_by!(uuid: params[:uuid])
    render json: ProjectCorrelationsQuery.call(principal: current_cli_access_token, project: cli_project, event:, from: params[:from], to: params[:to])
  rescue ProjectCorrelationsQuery::InvalidRange, ProjectCorrelationPolicy::TooManyProjects => error
    render json: { error: "invalid_query", message: error.message }, status: :unprocessable_content
  end
end
