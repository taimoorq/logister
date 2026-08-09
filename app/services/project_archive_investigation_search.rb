# frozen_string_literal: true

class ProjectArchiveInvestigationSearch
  HOT_RESULT_LIMIT = 25
  ARCHIVE_RESULT_LIMIT = 25
  MOBILE_EVENT_FILTER_EXPRESSIONS = {
    source: Arel.sql("COALESCE(NULLIF(ingest_events.context #>> '{telemetry_evidence,source}', ''), NULLIF(ingest_events.context #>> '{diagnostic,source}', ''))"),
    diagnostic_kind: Arel.sql("ingest_events.context #>> '{diagnostic,kind}'"),
    build_number: Arel.sql("COALESCE(NULLIF(ingest_events.context #>> '{app,version_code}', ''), NULLIF(ingest_events.context ->> 'build_number', ''))"),
    distribution_channel: Arel.sql("COALESCE(NULLIF(ingest_events.context #>> '{distribution,channel}', ''), NULLIF(ingest_events.context #>> '{distribution,track}', ''))"),
    platform: Arel.sql("COALESCE(NULLIF(ingest_events.context ->> 'apple_platform', ''), NULLIF(ingest_events.context #>> '{os,name}', ''))")
  }.freeze
  SEARCH_FIELDS = %w[
    q
    event_type
    trace_id
    request_id
    session_id
    user_id
    session_hash
    installation_hash
    user_hash
    environment
    release
    service
    route
    clock
    source
    diagnostic_kind
    build_number
    distribution_channel
    platform
    artifact_state
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

    @hot_events ||= hot_event_scope.order(event_time_column => :desc, id: :desc).limit(HOT_RESULT_LIMIT)
  end

  def hot_spans
    return TraceSpan.none unless query_present?
    return TraceSpan.none if mobile? && mobile_event_filters_present?

    @hot_spans ||= hot_span_scope.order(span_time_column => :desc, id: :desc).limit(HOT_RESULT_LIMIT)
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

  def mobile?
    project.integration_android? || project.integration_ios?
  end

  def clock
    value("clock").presence_in(%w[evidence receipt]) || (mobile? ? "receipt" : "evidence")
  end

  def clock_label
    clock == "receipt" ? "Receipt time" : "Evidence time"
  end

  def event_time(event)
    clock == "receipt" ? event.created_at : event.occurred_at
  end

  def mobile_summary(event)
    context = MobileTelemetryNormalizer.normalize(event.context)
    evidence = TelemetryEvidence.for(event)
    {
      source: evidence.source,
      kind: context.dig("diagnostic", "kind").presence || context.dig("error", "mechanism").presence,
      build: context.dig("app", "version_code").presence,
      channel: context.dig("distribution", "channel").presence,
      platform: context["apple_platform"].presence || context.dig("os", "name").presence,
      artifact_state: artifact_states_by_event_id[event.id]
    }.compact
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
    scope = apply_time_range(scope, event_time_column)
    scope = scope.where(event_type: value("event_type")) if value("event_type").present? && IngestEvent.event_types.key?(value("event_type"))
    scope = apply_context_filter(scope, "trace_id", "traceId", value("trace_id"))
    scope = apply_context_filter(scope, "request_id", "requestId", value("request_id"))
    scope = apply_context_filter(scope, "session_id", "sessionId", value("session_id"))
    scope = apply_context_filter(scope, "user_id", "userId", value("user_id"))
    scope = apply_context_filter(scope, "environment", nil, value("environment"))
    scope = apply_context_filter(scope, "release", nil, value("release"))
    scope = apply_context_filter(scope, "service", nil, value("service"))
    scope = apply_context_filter(scope, "route", nil, value("route"))
    scope = apply_mobile_event_filters(scope) if mobile?
    scope = apply_mobile_correlation_filters(scope) if mobile?
    scope = apply_text_query(scope, value("q"))
    scope
  end

  def hot_span_scope
    return TraceSpan.none if value("event_type").present? && value("event_type") != "span"

    scope = project.trace_spans
    scope = apply_time_range(scope, span_time_column)
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

  def apply_mobile_event_filters(scope)
    scope = apply_expression_filter(scope, MOBILE_EVENT_FILTER_EXPRESSIONS.fetch(:source), value("source"))
    scope = apply_expression_filter(scope, MOBILE_EVENT_FILTER_EXPRESSIONS.fetch(:diagnostic_kind), value("diagnostic_kind"))
    scope = apply_expression_filter(scope, MOBILE_EVENT_FILTER_EXPRESSIONS.fetch(:build_number), value("build_number"))
    scope = apply_expression_filter(scope, MOBILE_EVENT_FILTER_EXPRESSIONS.fetch(:distribution_channel), value("distribution_channel"))
    scope = apply_expression_filter(scope, MOBILE_EVENT_FILTER_EXPRESSIONS.fetch(:platform), value("platform"))
    if value("artifact_state").present?
      occurrence_ids = ErrorOccurrence.joins(:error_group)
        .where(error_groups: { project_id: project.id })
        .where(
          "error_occurrences.dimensions ->> 'mapping_status' = :state OR error_occurrences.dimensions ->> 'symbolication_status' = :state",
          state: value("artifact_state")
        )
        .select(:ingest_event_id)
      scope = scope.where(id: occurrence_ids)
    end
    scope
  end

  def mobile_event_filters_present?
    %w[source diagnostic_kind build_number distribution_channel platform artifact_state session_hash installation_hash user_hash].any? do |key|
      value(key).present?
    end
  end

  def apply_expression_filter(scope, expression_node, raw_value)
    return scope if raw_value.blank?

    scope.where(expression_node.eq(raw_value))
  end

  def apply_mobile_correlation_filters(scope)
    {
      "session_hash" => :session_hash,
      "installation_hash" => :installation_hash,
      "user_hash" => :user_hash
    }.each do |parameter, column|
      next if value(parameter).blank?

      occurrence_ids = ErrorOccurrence.joins(:error_group)
        .where(error_groups: { project_id: project.id })
        .where(column => value(parameter))
        .select(:ingest_event_id)
      scope = scope.where(id: occurrence_ids)
    end
    scope
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

  def event_time_column
    clock == "receipt" ? :created_at : :occurred_at
  end

  def span_time_column
    clock == "receipt" ? :created_at : :started_at
  end

  def artifact_states_by_event_id
    @artifact_states_by_event_id ||= begin
      event_ids = hot_events.map(&:id)
      ErrorOccurrence.joins(:error_group)
        .where(error_groups: { project_id: project.id }, ingest_event_id: event_ids)
        .pluck(:ingest_event_id, :dimensions)
        .each_with_object({}) do |(event_id, dimensions), result|
          values = dimensions.to_h
          result[event_id] = values["mapping_status"].presence || values["symbolication_status"].presence
        end
    end
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
