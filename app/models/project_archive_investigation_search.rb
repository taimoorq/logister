# frozen_string_literal: true

class ProjectArchiveInvestigationSearch
  HOT_RESULT_LIMIT = 25
  ARCHIVE_RESULT_LIMIT = 25
  SEARCH_FIELDS = %w[
    q
    event_type
    trace_id
    request_id
    session_id
    user_id
    environment
    release
    service
    route
    from
    to
  ].freeze

  def initialize(project:, params:)
    @project = project
    @params = normalize_params(params)
  end

  attr_reader :project, :params

  def query_present?
    params.values.any?(&:present?)
  end

  def hot_events
    return IngestEvent.none unless query_present?

    @hot_events ||= hot_event_scope.order(occurred_at: :desc, id: :desc).limit(HOT_RESULT_LIMIT)
  end

  def hot_spans
    return TraceSpan.none unless query_present?

    @hot_spans ||= hot_span_scope.order(started_at: :desc, id: :desc).limit(HOT_RESULT_LIMIT)
  end

  def archive_runs
    return TelemetryArchive.none unless query_present?

    @archive_runs ||= archive_run_scope.recent_first.limit(ARCHIVE_RESULT_LIMIT)
  end

  def total_hot_events
    return 0 unless query_present?

    @total_hot_events ||= hot_event_scope.count
  end

  def total_hot_spans
    return 0 unless query_present?

    @total_hot_spans ||= hot_span_scope.count
  end

  def total_archive_runs
    return 0 unless query_present?

    @total_archive_runs ||= archive_run_scope.count
  end

  def value(key)
    params[key.to_s]
  end

  private

  def normalize_params(raw_params)
    source = if raw_params.respond_to?(:to_unsafe_h)
      raw_params.to_unsafe_h
    else
      raw_params.to_h
    end

    SEARCH_FIELDS.index_with { |field| source[field].to_s.strip.presence }
  end

  def hot_event_scope
    return IngestEvent.none if value("event_type") == "span"

    scope = project.ingest_events
    scope = apply_time_range(scope, :occurred_at)
    scope = scope.where(event_type: value("event_type")) if value("event_type").present? && IngestEvent.event_types.key?(value("event_type"))
    scope = apply_context_filter(scope, "trace_id", "traceId", value("trace_id"))
    scope = apply_context_filter(scope, "request_id", "requestId", value("request_id"))
    scope = apply_context_filter(scope, "session_id", "sessionId", value("session_id"))
    scope = apply_context_filter(scope, "user_id", "userId", value("user_id"))
    scope = apply_context_filter(scope, "environment", nil, value("environment"))
    scope = apply_context_filter(scope, "release", nil, value("release"))
    scope = apply_context_filter(scope, "service", nil, value("service"))
    scope = apply_context_filter(scope, "route", nil, value("route"))
    scope = apply_text_query(scope, value("q"))
    scope
  end

  def hot_span_scope
    return TraceSpan.none if value("event_type").present? && value("event_type") != "span"

    scope = project.trace_spans
    scope = apply_time_range(scope, :started_at)
    scope = scope.where(trace_id: value("trace_id")) if value("trace_id").present?
    scope = apply_context_filter(scope, "request_id", "requestId", value("request_id"))
    scope = apply_context_filter(scope, "environment", nil, value("environment"))
    scope = apply_context_filter(scope, "release", nil, value("release"))
    scope = apply_context_filter(scope, "service", nil, value("service"))
    scope = apply_context_filter(scope, "route", nil, value("route"))
    scope = apply_span_text_query(scope, value("q"))
    scope
  end

  def archive_run_scope
    scope = project.telemetry_archives
    scope = scope.where(record_type: archive_record_types_for_event_type(value("event_type"))) if value("event_type").present?
    scope = apply_archive_time_range(scope)
    scope = apply_archive_text_query(scope, value("q"))
    scope
  end

  def apply_time_range(scope, column)
    timestamp_column = scope.klass.arel_table[column]

    if parsed_from
      scope = scope.where(timestamp_column.gteq(parsed_from))
    end
    if parsed_to
      scope = scope.where(timestamp_column.lteq(parsed_to))
    end
    scope
  end

  def apply_archive_time_range(scope)
    if parsed_from
      scope = scope.where("before_at >= ?", parsed_from)
    end
    if parsed_to
      scope = scope.where("COALESCE(after_at, before_at) <= ?", parsed_to)
    end
    scope
  end

  def apply_context_filter(scope, snake_key, camel_key, raw_value)
    return scope if raw_value.blank?

    if camel_key.present?
      scope.where("context ->> ? = ? OR context ->> ? = ?", snake_key, raw_value, camel_key, raw_value)
    else
      scope.where("context ->> ? = ?", snake_key, raw_value)
    end
  end

  def apply_text_query(scope, raw_query)
    return scope if raw_query.blank?

    query = raw_query.to_s.strip
    if uuid_like?(query)
      scope = scope.where(uuid: query).or(scope.where(fingerprint: query))
    elsif integer_like?(query)
      scope = scope.where(id: query.to_i).or(scope.where("message ILIKE ?", "%#{sanitize_like(query)}%"))
    else
      pattern = "%#{sanitize_like(query)}%"
      scope = scope.where("message ILIKE ? OR fingerprint ILIKE ?", pattern, pattern)
    end
    scope
  end

  def apply_span_text_query(scope, raw_query)
    return scope if raw_query.blank?

    query = raw_query.to_s.strip
    if uuid_like?(query)
      scope.where(uuid: query)
    elsif integer_like?(query)
      scope.where(id: query.to_i).or(scope.where("name ILIKE ? OR trace_id = ? OR span_id = ?", "%#{sanitize_like(query)}%", query, query))
    else
      pattern = "%#{sanitize_like(query)}%"
      scope.where("name ILIKE ? OR trace_id = ? OR span_id = ?", pattern, query, query)
    end
  end

  def apply_archive_text_query(scope, raw_query)
    return scope if raw_query.blank?

    pattern = "%#{sanitize_like(raw_query)}%"
    scope.where("objects::text ILIKE ? OR error_message ILIKE ?", pattern, pattern)
  end

  def archive_record_types_for_event_type(event_type)
    event_type == "span" ? "trace_spans" : "ingest_events"
  end

  def parsed_from
    @parsed_from ||= parse_time(value("from"))
  end

  def parsed_to
    @parsed_to ||= parse_time(value("to"))
  end

  def parse_time(raw_value)
    return if raw_value.blank?

    Time.zone.parse(raw_value)
  rescue ArgumentError, TypeError
    nil
  end

  def uuid_like?(value)
    value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
  end

  def integer_like?(value)
    value.match?(/\A\d+\z/)
  end

  def sanitize_like(value)
    ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)
  end
end
