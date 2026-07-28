# frozen_string_literal: true

class Api::V1::Cli::BaseController < ApplicationController
  include Api::V1::Cli::EventFiltering

  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false

  before_action :authenticate_cli_access_token!
  after_action :touch_cli_access_token_last_used

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  attr_reader :current_cli_access_token

  def authenticate_cli_access_token!
    token = bearer_token
    @current_cli_access_token = CliAccessToken.authenticate(token)

    return if @current_cli_access_token

    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def require_cli_scopes!(*scopes)
    return if performed?
    return if current_cli_access_token&.allows_scopes?(*scopes)

    render json: { error: "Forbidden", required_scopes: scopes }, status: :forbidden
  end

  def cli_project
    @cli_project ||= begin
      identifier = params[:project_uuid].presence || params[:project_id].presence || params[:uuid].presence
      raise ActiveRecord::RecordNotFound, "Project not found" if identifier.blank?

      current_cli_access_token.accessible_projects.find_by!(uuid: identifier)
    rescue ActiveRecord::RecordNotFound
      current_cli_access_token.accessible_projects.find_by!(slug: identifier)
    end
  end

  def cli_limit(default: 50, max: 100)
    raw = params[:limit].presence || default
    value = raw.to_i
    return default unless value.positive?

    [ value, max ].min
  end

  def parse_cli_time(value)
    return if value.blank?

    Time.zone.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def cli_since(default: nil)
    raw = params[:since].to_s.strip
    return default if raw.blank?

    case raw
    when /\A(\d+)(m|h|d|w)\z/
      amount = Regexp.last_match(1).to_i
      unit = Regexp.last_match(2)
      amount.public_send({ "m" => :minutes, "h" => :hours, "d" => :days, "w" => :weeks }.fetch(unit)).ago
    else
      parse_cli_time(raw) || default
    end
  end

  def render_not_found
    render json: { error: "Not found" }, status: :not_found
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
