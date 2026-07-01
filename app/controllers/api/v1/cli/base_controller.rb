# frozen_string_literal: true

class Api::V1::Cli::BaseController < ApplicationController
  EVENT_ERROR_LEVELS = %w[error fatal].freeze
  NUMERIC_PATTERN = "^[0-9]+(\\.[0-9]+)?$"
  STATUS_PATTERN = "^[0-9]+$"
  EVENT_DURATION_SQL = <<~SQL.squish
    COALESCE(
      NULLIF(ingest_events.context->>'duration_ms', ''),
      NULLIF(ingest_events.context->>'durationMs', '')
    )
  SQL

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

  def apply_event_common_filters(scope)
    event_type = (params[:event_type].presence || params[:type].presence).to_s
    if event_type.present? && event_type != "all"
      event_types = event_type.split(",").map(&:strip).select { |type| IngestEvent.event_types.key?(type) }
      scope = scope.where(event_type: event_types) if event_types.any?
    end

    levels = params[:level].to_s.split(",").map(&:strip).reject(&:blank?)
    scope = scope.where(level: levels) if levels.any?
    scope = scope.where("occurred_at >= ?", cli_since) if cli_since.present?
    scope = scope.where("occurred_at <= ?", parse_cli_time(params[:until])) if parse_cli_time(params[:until]).present?
    scope = scope.where("COALESCE(NULLIF(context->>'environment', ''), 'production') = ?", params[:environment].presence || params[:env].presence) if params[:environment].present? || params[:env].present?
    scope = scope.where("context->>'release' = ?", params[:release]) if params[:release].present?
    scope = scope.where("context->>'trace_id' = ? OR context->>'traceId' = ? OR context->'trace'->>'traceId' = ?", params[:trace_id], params[:trace_id], params[:trace_id]) if params[:trace_id].present?
    scope = scope.where("context->>'request_id' = ? OR context->>'requestId' = ? OR context->'trace'->>'requestId' = ?", params[:request_id], params[:request_id], params[:request_id]) if params[:request_id].present?
    scope = apply_event_status_filter(scope, params[:status])
    scope = apply_event_min_duration_filter(scope, params[:min_duration_ms])
    scope = apply_event_text_filter(scope, params[:q].presence || params[:query].presence)
    scope
  end

  def apply_event_status_filter(scope, status)
    normalized = status.to_s.strip.downcase
    return scope if normalized.blank? || normalized == "all"

    case normalized
    when "errored", "error", "failed"
      scope.where(errored_event_status_sql, levels: EVENT_ERROR_LEVELS, status_pattern: STATUS_PATTERN)
    when "ok", "success", "successful"
      scope.where("COALESCE(ingest_events.level, '') NOT IN (?)", EVENT_ERROR_LEVELS)
           .where(ok_event_status_sql, status_pattern: STATUS_PATTERN)
    else
      statuses = normalized.split(",").map(&:strip).reject(&:blank?)
      scope.where(
        "LOWER(COALESCE(ingest_events.context->>'status', ingest_events.context->>'check_in_status', '')) IN (?)",
        statuses
      )
    end
  end

  def errored_event_status_sql
    <<~SQL.squish
      COALESCE(ingest_events.level, '') IN (:levels)
      OR LOWER(COALESCE(ingest_events.context->>'status', ingest_events.context->>'check_in_status', '')) IN ('error', 'errored', 'failed')
      OR (
        ingest_events.context->>'status' ~ :status_pattern
        AND (ingest_events.context->>'status')::integer >= 500
      )
    SQL
  end

  def ok_event_status_sql
    <<~SQL.squish
      LOWER(COALESCE(ingest_events.context->>'status', ingest_events.context->>'check_in_status', '')) NOT IN ('error', 'errored', 'failed')
      AND (
        ingest_events.context->>'status' IS NULL
        OR ingest_events.context->>'status' !~ :status_pattern
        OR (ingest_events.context->>'status')::integer < 500
      )
    SQL
  end

  def apply_event_min_duration_filter(scope, minimum)
    raw = minimum.to_s.strip
    return scope unless raw.match?(/\A[0-9]+(\.[0-9]+)?\z/)

    condition_sql = [
      "(",
      EVENT_DURATION_SQL,
      ") ~ :numeric_pattern AND (",
      EVENT_DURATION_SQL,
      ")::numeric >= :minimum"
    ].join

    scope.where(condition_sql, numeric_pattern: NUMERIC_PATTERN, minimum: raw.to_f)
  end

  def apply_event_text_filter(scope, query)
    return scope if query.blank?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    scope.where(
      <<~SQL.squish,
        LOWER(ingest_events.message) LIKE :term
        OR LOWER(COALESCE(ingest_events.level, '')) LIKE :term
        OR LOWER(COALESCE(ingest_events.fingerprint, '')) LIKE :term
        OR LOWER(COALESCE(ingest_events.context->>'transaction_name', ingest_events.context->>'transactionName', ingest_events.context->>'name', ingest_events.context->>'check_in_slug', ingest_events.context->>'logger_name', ingest_events.context->>'release', '')) LIKE :term
      SQL
      term: term
    )
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
