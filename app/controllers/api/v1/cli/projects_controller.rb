# frozen_string_literal: true

class Api::V1::Cli::ProjectsController < Api::V1::Cli::BaseController
  before_action -> { require_cli_scopes!("projects:read") }

  def index
    projects = current_cli_access_token.accessible_projects.order(:name, :id)
    projects = projects.active unless ActiveModel::Type::Boolean.new.cast(params[:include_archived])

    render json: {
      items: projects.limit(cli_limit(default: 100, max: 500)).map { |project| Logister::CliSerializer.project(project) }
    }
  end

  def show
    render json: Logister::CliSerializer.project(cli_project)
  end
end
