# frozen_string_literal: true

class Api::V1::Cli::EventsController < Api::V1::Cli::BaseController
  before_action -> { require_cli_scopes!("events:read") }

  def index
    scope = apply_event_common_filters(cli_project.ingest_events)
            .includes(:error_group)
            .order(occurred_at: :desc, id: :desc)
            .limit(cli_limit)

    render json: {
      items: scope.map { |event| Logister::CliSerializer.event(event, include_context: include_context?) }
    }
  end

  def show
    event = cli_project.ingest_events.includes(:error_group).find_by!(uuid: params[:uuid])

    render json: Logister::CliSerializer.event(event, include_context: true)
  end

  private

  def include_context?
    !ActiveModel::Type::Boolean.new.cast(params[:summary])
  end
end
