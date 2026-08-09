# frozen_string_literal: true

class Api::V1::Cli::SessionsController < Api::V1::Cli::BaseController
  PROJECT_UUID_LIMIT = 100

  def show
    projects = current_cli_access_token.accessible_projects
    project_count = projects.count
    project_uuids = projects.order(:created_at, :uuid).limit(PROJECT_UUID_LIMIT).pluck(:uuid)

    render json: {
      token: {
        uuid: current_cli_access_token.uuid,
        name: current_cli_access_token.name,
        scopes: current_cli_access_token.scopes,
        expires_at: Logister::CliSerializer.timestamp(current_cli_access_token.expires_at),
        created_at: Logister::CliSerializer.timestamp(current_cli_access_token.created_at),
        last_used_at: Logister::CliSerializer.timestamp(current_cli_access_token.last_used_at),
        all_projects: current_cli_access_token.all_projects?
      }.compact,
      accessible_project_count: project_count,
      accessible_project_uuids: project_uuids,
      accessible_projects_truncated: project_count > project_uuids.length,
      missing_recommended_scopes: CliAccessToken::READ_SCOPES - current_cli_access_token.scopes,
      generated_at: Logister::CliSerializer.timestamp(Time.current)
    }
  end
end
