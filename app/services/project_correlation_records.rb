# frozen_string_literal: true

# Storage-only bounded reader. Callers must resolve and recheck ProjectCorrelationPolicy.
class ProjectCorrelationRecords
  LIMIT = 500
  SIGNALS = %w[error log transaction span].freeze
  CONTEXT_FIELDS = {
    "app_version" => [ %w[app version_name] ],
    "build_number" => [ %w[app version_code] ],
    "device_model" => [ %w[device model] ],
    "os_version" => [ %w[os version] ],
    "http_method" => [ %w[http method], %w[method], %w[http.method] ],
    "http_status_code" => [ %w[http status_code], %w[status_code], %w[http.status_code] ],
    "failure_kind" => [ %w[http failure_kind] ],
    "duration_scope" => [ %w[http duration_scope] ],
    "attempt" => [ %w[http attempt] ]
  }.freeze

  def initialize(from:, to:, identities: nil, limit: LIMIT, uuid: nil, filters: {}, newest_first: false)
    @from, @to, @identities, @uuid = from, to, identities, uuid
    @filters = filters.symbolize_keys.slice(:release, :build_number, :app_version, :event_uuids)
    @direction = newest_first ? :desc : :asc
    @limit = limit.to_i.clamp(1, LIMIT)
    raise ArgumentError, "Too many correlation identities" if identities && identities.size > LIMIT
  end

  def call(project:, environments:, signals: SIGNALS)
    result = { rows: [], coverage: [], truncated: false }
    Logister::CliPostgresStatementTimeout.call do
      (signals & SIGNALS).each do |signal|
        read = Logister::ClickhouseReadRouter.call(
          project_ids: [ project.id ], signals: [ signal ], from: @from, to: @to,
          clickhouse: ->(client) { clickhouse_rows(client, project, environments, signal) },
          postgres: -> { postgres_rows(project, environments, signal) }
        )
        result[:coverage] << { project_uuid: project.uuid, signal:, **read.diagnostics }
        result[:truncated] ||= read.payload.size > @limit
        result[:rows].concat(read.payload.first(@limit).map { |row| row.merge("type" => signal) })
      end
    end
    result[:partial] = result[:truncated] || result[:coverage].any? { |row| row[:partial] }
    result
  end

  private

  def predicate(trace, request, quote)
    return "1=1" if @identities.nil?
    traces = @identities.filter_map { |ids| ids.matchable("trace_id") }.uniq
    requests = @identities.filter_map { |ids| ids.matchable("request_id") }.uniq
    # This is a candidate lookup. The caller must reject contradictory trace IDs per pair.
    clauses = []
    clauses << "#{trace} IN (#{traces.map { |id| quote.call(id) }.join(', ')})" if traces.any?
    clauses << "#{request} IN (#{requests.map { |id| quote.call(id) }.join(', ')})" if requests.any?
    clauses.empty? ? "1=0" : "(#{clauses.join(' OR ')})"
  end

  def detail_fields(span, store)
    fields = CONTEXT_FIELDS.map do |name, paths|
      expressions = paths.map do |path|
        if store == :postgres
          "NULLIF(context #>> '{#{path.join(',')}}', '')"
        else
          "nullIf(JSON_VALUE(context_json, #{quote('$' + path.map { |key| ".\"#{key}\"" }.join)}), '')"
        end
      end
      value = expressions.size == 1 ? expressions.first : "COALESCE(#{expressions.join(', ')})"
      "#{store == :postgres ? 'LEFT' : 'leftUTF8'}(#{value}, 100) AS #{name}"
    end
    if span
      fields + [ "duration_ms", "status", "kind" ]
    elsif store == :postgres
      fields + [ "LEFT(context->>'duration_ms', 40) AS duration_ms", "LEFT(context->>'status', 40) AS status", "NULL AS kind" ]
    else
      fields + [ "duration_ms", "leftUTF8(JSONExtractString(context_json, 'status'), 40) AS status", "'' AS kind" ]
    end
  end

  def postgres_rows(project, environments, signal)
    span = signal == "span"
    table, timestamp = span ? %w[trace_spans started_at] : %w[ingest_events occurred_at]
    scope = span ? project.trace_spans : project.ingest_events.where(event_type: signal)
    ids = %w[trace_id request_id span_id parent_span_id].to_h do |key|
      [ key, span && key != "request_id" ? "#{table}.#{key}" : CorrelationContext.postgres(key, matchable: true) ]
    end
    scope = scope.where(timestamp => @from...@to)
      .where("COALESCE(NULLIF(context->>'environment', ''), 'production') IN (?)", environments)
      .where(predicate(ids["trace_id"], ids["request_id"], ActiveRecord::Base.connection.method(:quote)))
    scope = scope.where(uuid: @uuid) if @uuid
    @filters.each do |key, value|
      if key == :event_uuids
        scope = scope.where(uuid: value)
      else
        path = key == :release ? [ "release" ] : CONTEXT_FIELDS.fetch(key.to_s).first
        scope = scope.where("context #>> ? = ?", "{#{path.join(',')}}", value)
      end
    end
    ids.each do |key, sql|
      canonical = CorrelationContext.postgres(key)
      matchable = CorrelationContext.postgres(key, matchable: true)
      scope = scope.where(Arel.sql(canonical).eq(nil).or(Arel.sql(matchable).not_eq(nil)))
      if span && key != "request_id"
        scope = scope.where(Arel.sql("(NULLIF(#{sql}, '') IS NULL OR #{sql} ~ '^[A-Za-z0-9._:-]{1,128}$')"))
          .where(Arel.sql(canonical).eq(nil).or(Arel.sql(canonical).eq(Arel.sql(sql))))
      end
    end
    # Aggregated mobile diagnostics are never evidence of a single request.
    scope = scope.where("COALESCE(context #>> '{telemetry_evidence,time,precision}', '') NOT IN ('reporting_interval', 'received_only')")
    operation = "COALESCE(NULLIF(context->>'route', ''), NULLIF(context->>'http.route', ''), NULLIF(context->>'transaction_name', '')#{span ? ', name' : ''})"
    fields = [ "uuid", "#{timestamp} AS occurred_at", *ids.map { |key, sql| "#{sql} AS #{key}" },
      "LEFT(context->>'environment', 100) AS environment", "LEFT(context->>'release', 200) AS release",
      "LEFT(#{operation}, 512) AS operation", *detail_fields(span, :postgres) ]
    scope.reselect(Arel.sql(fields.join(", "))).order(timestamp => @direction, uuid: @direction).limit(@limit + 1)
      .map { |row| row.attributes }
  end

  def clickhouse_rows(client, project, environments, signal)
    span = signal == "span"
    timestamp = span ? "started_at" : "occurred_at"
    ids = %w[trace_id request_id span_id parent_span_id].to_h do |key|
      [ key, span && key != "request_id" ? (key == "span_id" ? "external_span_id" : key) : CorrelationContext.clickhouse(key, matchable: true) ]
    end
    clauses = [ "project_id = #{project.id.to_i}",
      "#{timestamp} >= parseDateTime64BestEffort(#{quote(@from.utc.iso8601(6))}, 6)",
      "#{timestamp} < parseDateTime64BestEffort(#{quote(@to.utc.iso8601(6))}, 6)",
      "environment IN (#{environments.map { |e| quote(e) }.join(', ')})",
      "JSONExtractString(context_json, 'telemetry_evidence', 'time', 'precision') NOT IN ('reporting_interval', 'received_only')",
      predicate(ids["trace_id"], ids["request_id"], method(:quote)) ]
    ids.each do |key, sql|
      canonical = CorrelationContext.clickhouse(key)
      matchable = CorrelationContext.clickhouse(key, matchable: true)
      clauses << "(#{canonical} = '' OR #{matchable} != '')"
      if span && key != "request_id"
        clauses << "(#{sql} = '' OR match(#{sql}, '^[A-Za-z0-9._:-]{1,128}$'))"
        clauses << "(#{canonical} = '' OR #{canonical} = #{sql})"
      end
    end
    clauses << "event_type = #{quote(signal)}" unless span
    clauses << "toString(#{span ? 'span_id' : 'event_id'}) = #{quote(@uuid)}" if @uuid
    @filters.each do |key, value|
      if key == :event_uuids
        clauses << (value.empty? ? "1=0" : "toString(#{span ? 'span_id' : 'event_id'}) IN (#{value.map { |id| quote(id) }.join(', ')})")
      else
        path = key == :release ? [ "release" ] : CONTEXT_FIELDS.fetch(key.to_s).first
        json_path = "$" + path.map { |part| ".\"#{part}\"" }.join
        clauses << "JSON_VALUE(context_json, #{quote(json_path)}) = #{quote(value)}"
      end
    end
    client.select_rows!(<<~SQL.squish)
      SELECT toString(#{span ? 'span_id' : 'event_id'}) AS uuid, #{timestamp} AS occurred_at,
        #{ids.map { |key, sql| "#{sql} AS correlation_#{key}" }.join(', ')},
        leftUTF8(environment, 100) AS environment, leftUTF8(release, 200) AS release,
        leftUTF8(#{span ? 'route' : 'transaction_name'}, 512) AS operation,
        #{detail_fields(span, :clickhouse).join(", ")}
      FROM #{span ? client.span_facts_table_name : client.event_facts_table_name}
      WHERE #{clauses.join(' AND ')} ORDER BY #{timestamp} #{@direction}, #{span ? 'span_id' : 'event_id'} #{@direction}
      LIMIT #{@limit + 1}
    SQL
      .map { |row| row.transform_keys { |key| key.delete_prefix("correlation_") } }
  end

  def quote(value)
    "'#{value.to_s.gsub('\\') { '\\\\' }.gsub("'") { "\\'" }}'"
  end
end
