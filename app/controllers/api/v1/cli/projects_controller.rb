# frozen_string_literal: true

class Api::V1::Cli::ProjectsController < Api::V1::Cli::BaseController
  CURSOR_RESOURCE = "projects"

  before_action -> { require_cli_scopes!("projects:read") }

  def index
    projects = current_cli_access_token.accessible_projects.order(:name, :id)
    include_archived = ActiveModel::Type::Boolean.new.cast(params[:include_archived])
    projects = projects.active unless include_archived
    filters = { include_archived: }
    cursor = decode_cli_cursor(
      params[:cursor],
      resource: CURSOR_RESOURCE,
      project_uuid: current_cli_access_token.uuid,
      filters:
    )
    projects = projects.where("(projects.created_at, projects.uuid) < (?, ?::uuid)", cursor[:timestamp], cursor[:uuid]) if cursor
    limit = cli_limit(default: 100, max: 100)
    records = projects.reorder(created_at: :desc, uuid: :desc).limit(limit + 1).to_a
    has_more = records.length > limit
    records = records.first(limit)
    next_cursor = if has_more && records.last
      encode_cli_cursor(
        resource: CURSOR_RESOURCE,
        project_uuid: current_cli_access_token.uuid,
        filters:,
        timestamp: records.last.created_at,
        uuid: records.last.uuid
      )
    end

    render json: cli_list_payload(
      items: records.map { |project| Logister::CliSerializer.project(project) },
      next_cursor:
    )
  end

  def show
    render json: Logister::CliSerializer.project(cli_project)
  end
end
