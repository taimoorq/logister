# frozen_string_literal: true

class Api::V1::Cli::BaseController < ApplicationController
  class AmbiguousProject < StandardError
    attr_reader :identifier

    def initialize(identifier)
      @identifier = identifier
      super("More than one accessible project uses this slug")
    end
  end

  include Api::V1::Cli::EventFiltering
  include Api::V1::Cli::ReadRateLimitGuard

  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false

  before_action :enforce_cli_pre_auth_rate_limit!
  before_action :authenticate_cli_access_token!
  before_action :enforce_cli_read_rate_limit!
  around_action :with_cli_postgres_statement_timeout
  after_action :touch_cli_access_token_last_used

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from AmbiguousProject, with: :render_ambiguous_project
  rescue_from Logister::CliCursor::InvalidCursor, with: :render_invalid_cursor
  rescue_from Logister::CliQuery::InvalidParameter, with: :render_invalid_parameter
  rescue_from ActiveRecord::QueryCanceled, with: :render_query_timeout

  private

  attr_reader :current_cli_access_token

  def authenticate_cli_access_token!
    token = bearer_token
    @current_cli_access_token = CliAccessToken.authenticate(token)

    return if @current_cli_access_token

    render json: {
      error: "Unauthorized",
      code: "unauthorized",
      message: "Provide an active Logister CLI access token."
    }, status: :unauthorized
  end

  def require_cli_scopes!(*scopes)
    return if performed?
    return if current_cli_access_token&.allows_scopes?(*scopes)

    render json: {
      error: "Forbidden",
      code: "insufficient_scope",
      message: "Log in again to grant the required scopes.",
      required_scopes: scopes
    }, status: :forbidden
  end

  def require_cli_project_manager!
    return if performed?
    return if cli_project.managed_by?(current_cli_access_token.user)

    render json: {
      error: "Forbidden",
      code: "project_manager_required",
      message: "Artifact uploads require project owner or admin access."
    }, status: :forbidden
  end

  def cli_project
    @cli_project ||= begin
      identifier = params[:project_uuid].presence || params[:project_id].presence || params[:uuid].presence
      raise ActiveRecord::RecordNotFound, "Project not found" if identifier.blank?

      projects = current_cli_access_token.accessible_projects
      project = projects.find_by(uuid: identifier)
      if project
        project
      else
        matches = projects.where(slug: identifier).limit(2).to_a
        raise ActiveRecord::RecordNotFound, "Project not found" if matches.empty?
        raise AmbiguousProject, identifier if matches.many?

        matches.first
      end
    end
  end

  def cli_limit(default: 50, max: 100)
    Logister::CliQuery.integer(params[:limit], parameter: "limit", default:, min: 1, max:)
  end

  def parse_cli_time(value)
    Logister::CliQuery.time(value, parameter: "timestamp")
  end

  def cli_since(default: nil)
    raw = params[:since].to_s.strip
    return default if raw.blank?

    Logister::CliQuery.relative_or_time(raw, parameter: "since")
  end

  def cli_time_range(default_duration: 24.hours, max_duration: 90.days)
    Logister::CliQuery.range(
      since_value: params[:since],
      until_value: params[:until],
      default_duration:,
      max_duration:
    )
  end

  def decode_cli_cursor(value, resource:, project_uuid:, filters:)
    return if value.blank?

    Logister::CliCursor.decode(value, resource:, project_uuid:, filters:)
  end

  def encode_cli_cursor(resource:, project_uuid:, filters:, timestamp:, uuid:)
    Logister::CliCursor.encode(resource:, project_uuid:, filters:, timestamp:, uuid:)
  end

  def cli_list_payload(items:, next_cursor: nil, generated_at: Time.current, **metadata)
    {
      items:,
      next_cursor:,
      generated_at: Logister::CliSerializer.timestamp(generated_at)
    }.merge(metadata).compact
  end

  def render_not_found
    render json: {
      error: "Not found",
      code: "not_found",
      message: "The requested resource was not found."
    }, status: :not_found
  end

  def render_ambiguous_project(error)
    render json: {
      error: "Ambiguous project",
      code: "ambiguous_project",
      message: "More than one accessible project uses '#{error.identifier}'. Use the project UUID instead."
    }, status: :conflict
  end

  def render_invalid_cursor
    render json: {
      error: "Invalid cursor",
      code: "invalid_cursor",
      message: "The cursor is invalid or does not match this project and filter set."
    }, status: :unprocessable_content
  end

  def render_invalid_parameter(error)
    render json: {
      error: "Invalid parameter",
      code: "invalid_parameter",
      message: error.message,
      parameter: error.parameter
    }.compact, status: :unprocessable_content
  end

  def render_query_timeout
    render json: {
      error: "Query unavailable",
      code: "query_timeout",
      message: "The query exceeded the server time limit. Narrow the time range or filters and try again."
    }, status: :service_unavailable
  end

  def with_cli_postgres_statement_timeout(&)
    Logister::CliPostgresStatementTimeout.call(&)
  end

  def touch_cli_access_token_last_used
    current_cli_access_token&.touch_last_used! unless performed? && response.status == 401
  end

  def bearer_token
    authorization = request.headers["Authorization"].to_s
    return authorization.delete_prefix("Bearer ").strip if authorization.start_with?("Bearer ")

    nil
  end
end
