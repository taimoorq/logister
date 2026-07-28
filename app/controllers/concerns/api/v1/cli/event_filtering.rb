# frozen_string_literal: true

module Api::V1::Cli::EventFiltering
  extend ActiveSupport::Concern

  EVENT_ERROR_LEVELS = %w[error fatal].freeze
  NUMERIC_PATTERN = "^[0-9]+(\\.[0-9]+)?$"
  STATUS_PATTERN = "^[0-9]+$"
  EVENT_DURATION_SQL = <<~SQL.squish
    COALESCE(
      NULLIF(ingest_events.context->>'duration_ms', ''),
      NULLIF(ingest_events.context->>'durationMs', '')
    )
  SQL

  private

  def apply_event_common_filters(scope)
    scope = apply_event_type_filter(scope)
    scope = apply_event_level_filter(scope)
    scope = apply_event_time_filters(scope)
    scope = apply_event_context_filters(scope)
    scope = apply_event_status_filter(scope, params[:status])
    scope = apply_event_min_duration_filter(scope, params[:min_duration_ms])
    apply_event_text_filter(scope, params[:q].presence || params[:query].presence)
  end

  def apply_event_type_filter(scope)
    requested = (params[:event_type].presence || params[:type].presence).to_s
    return scope if requested.blank? || requested == "all"

    event_types = comma_separated_values(requested).select { |type| IngestEvent.event_types.key?(type) }
    event_types.any? ? scope.where(event_type: event_types) : scope
  end

  def apply_event_level_filter(scope)
    levels = comma_separated_values(params[:level])
    levels.any? ? scope.where(level: levels) : scope
  end

  def apply_event_time_filters(scope)
    since = cli_since
    until_time = parse_cli_time(params[:until])
    scope = scope.where("occurred_at >= ?", since) if since.present?
    scope = scope.where("occurred_at <= ?", until_time) if until_time.present?
    scope
  end

  def apply_event_context_filters(scope)
    environment = params[:environment].presence || params[:env].presence
    scope = scope.where("COALESCE(NULLIF(context->>'environment', ''), 'production') = ?", environment) if environment.present?
    scope = scope.where("context->>'release' = ?", params[:release]) if params[:release].present?
    scope = apply_trace_id_filter(scope)
    apply_request_id_filter(scope)
  end

  def apply_trace_id_filter(scope)
    return scope if params[:trace_id].blank?

    scope.where(
      "context->>'trace_id' = ? OR context->>'traceId' = ? OR context->'trace'->>'traceId' = ?",
      params[:trace_id], params[:trace_id], params[:trace_id]
    )
  end

  def apply_request_id_filter(scope)
    return scope if params[:request_id].blank?

    scope.where(
      "context->>'request_id' = ? OR context->>'requestId' = ? OR context->'trace'->>'requestId' = ?",
      params[:request_id], params[:request_id], params[:request_id]
    )
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
      scope.where(
        "LOWER(COALESCE(ingest_events.context->>'status', ingest_events.context->>'check_in_status', '')) IN (?)",
        comma_separated_values(normalized)
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
      "(", EVENT_DURATION_SQL, ") ~ :numeric_pattern AND (",
      EVENT_DURATION_SQL, ")::numeric >= :minimum"
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

  def comma_separated_values(value)
    value.to_s.split(",").filter_map { |item| item.strip.presence }
  end
end
