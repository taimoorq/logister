# frozen_string_literal: true

class Api::V1::Cli::BaseController < ApplicationController
  class AmbiguousProject < StandardError
    attr_reader :identifier

    def initialize(identifier)
      @identifier = identifier
      super("More than one accessible project uses this slug")
    end
  end

  include Api::V1::Cli::Responses
  include Api::V1::Cli::QueryParameters
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
