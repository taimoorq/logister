# frozen_string_literal: true

# A bounded occurrence lookup. A project link never grants read permission.
class ProjectCorrelationsQuery
  LIMIT = 500
  BYTES_LIMIT = 1.megabyte
  SIGNALS = %w[error log transaction span].freeze
  class InvalidRange < StandardError; end

  def self.call(...) = new(...).call

  def initialize(principal:, project:, event:, from: nil, to: nil)
    @principal, @project, @event = principal, project, event
    @from = parse_time(from) || event.occurred_at - 15.minutes
    @to = parse_time(to) || event.occurred_at + 15.minutes
    raise InvalidRange, "Choose a time range of up to 24 hours." unless @to > @from && @to - @from <= 24.hours
    @ids = CorrelationContext.new(event.context)
  end

  def call
    raise ActiveRecord::RecordNotFound unless ProjectCorrelationPolicy.enabled?(@project)
    scope = ProjectCorrelationPolicy.projects(principal: @principal, anchor: @project, environment: IngestEvent.environment(@event))
    result = { items: [], coverage: [], from: @from.iso8601(3), to: @to.iso8601(3), truncated: false, partial: false }
    evidence = TelemetryEvidence.for(@event)
    if evidence.reporting_interval? || evidence.received_only? || (@ids.conflicts & %w[trace_id request_id]).any? || (@ids.matchable("trace_id").blank? && @ids.matchable("request_id").blank?)
      return result.merge(reason: "This occurrence has no unambiguous request identifiers.")
    end

    projects = @principal.accessible_projects.where(id: scope.keys).index_by(&:id)
    Logister::CliPostgresStatementTimeout.call do
      scope.each do |id, environments|
        project = projects.fetch(id)
        SIGNALS.each do |signal|
          read = Logister::ClickhouseReadRouter.call(
            project_ids: [ id ], signals: [ signal ], from: @from, to: @to,
            clickhouse: ->(client) { clickhouse_rows(client, project, environments, signal) },
            postgres: -> { postgres_rows(project, environments, signal) }
          )
          result[:coverage] << { project_uuid: project.uuid, signal:, **read.diagnostics }
          result[:truncated] ||= read.payload.size > LIMIT
          result[:items].concat(read.payload.first(LIMIT).map { |row| summarize(row, project, signal) })
        end
      end
    end
    # Re-resolve membership and links before returning; no cached cross-project authorization.
    fresh = ProjectCorrelationPolicy.projects(principal: @principal, anchor: @project, environment: IngestEvent.environment(@event))
    visible = projects.values.select { |p| fresh.key?(p.id) }.to_h { |p| [ p.uuid, fresh[p.id] ] }
    result[:coverage].select! { |row| visible.include?(row[:project_uuid]) }
    items = result[:items].select { |row| visible.fetch(row[:project_uuid], []).include?(row[:environment]) }
      .reject { |row| row[:project_uuid] == @project.uuid && row[:uuid] == @event.uuid }
      .sort_by { |row| [ row[:occurred_at], row[:project_uuid], row[:uuid] ] }
    result[:truncated] ||= items.size > LIMIT
    bytes = JSON.generate(result.except(:items)).bytesize
    result[:items] = items.first(LIMIT).take_while do |item|
      bytes += JSON.generate(item).bytesize + 1
      bytes < BYTES_LIMIT
    end
    result[:truncated] ||= result[:items].size < items.size
    result[:partial] = result[:truncated] || result[:coverage].any? { |row| row[:partial] }
    result
  end

  private

  def parse_time(value)
    Time.iso8601(value.to_s) if value.present?
  rescue ArgumentError
    raise InvalidRange, "Use an ISO 8601 timestamp."
  end

  def predicate(trace, request, quote)
    clauses = []
    trace_id, request_id = @ids.matchable("trace_id"), @ids.matchable("request_id")
    clauses << "#{trace} = #{quote.call(trace_id)}" if trace_id
    if request_id
      condition = "#{request} = #{quote.call(request_id)}"
      condition += " AND (#{trace} IS NULL OR #{trace} = '' OR #{trace} = #{quote.call(trace_id)})" if trace_id
      clauses << "(#{condition})"
    end
    "(#{clauses.join(' OR ')})"
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
      "LEFT(#{operation}, 512) AS operation" ]
    scope.reselect(Arel.sql(fields.join(", "))).order(timestamp => :asc, uuid: :asc).limit(LIMIT + 1)
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
    client.select_rows!(<<~SQL.squish)
      SELECT toString(#{span ? 'span_id' : 'event_id'}) AS uuid, #{timestamp} AS occurred_at,
        #{ids.map { |key, sql| "#{sql} AS correlation_#{key}" }.join(', ')},
        leftUTF8(environment, 100) AS environment, leftUTF8(release, 200) AS release,
        leftUTF8(#{span ? 'route' : 'transaction_name'}, 512) AS operation
      FROM #{span ? client.span_facts_table_name : client.event_facts_table_name}
      WHERE #{clauses.join(' AND ')} ORDER BY #{timestamp} ASC, #{span ? 'span_id' : 'event_id'} ASC
      LIMIT #{LIMIT + 1}
    SQL
      .map { |row| row.transform_keys { |key| key.delete_prefix("correlation_") } }
  end

  def summarize(row, project, signal)
    trace = @ids.matchable("trace_id")
    same_trace = trace.present? && row["trace_id"] == trace
    parent = same_trace && ((@ids.matchable("span_id").present? && row["parent_span_id"] == @ids.matchable("span_id")) ||
      (@ids.matchable("parent_span_id").present? && row["span_id"] == @ids.matchable("parent_span_id")))
    at = row["occurred_at"].is_a?(String) ? Time.zone.parse(row["occurred_at"]) : row["occurred_at"]
    {
      project_uuid: project.uuid, project_name: project.name.truncate(100), uuid: row["uuid"], type: signal,
      occurred_at: at.utc.iso8601(3), evidence: parent ? "parent_span" : (same_trace ? "shared_trace" : "shared_request_id"),
      trace_id: row["trace_id"].presence, span_id: row["span_id"].presence, parent_span_id: row["parent_span_id"].presence,
      request_id: row["request_id"].presence, environment: row["environment"].presence || "production",
      release: row["release"].presence, operation: row["operation"].to_s.split(/[?#]/).first.presence,
      deployment: deployment(project, row, at)
    }.compact
  end

  def deployment(project, row, at)
    return if row["release"].blank?
    @deployments ||= {}
    key = [ project.id, row["environment"].presence || "production", row["release"] ]
    candidates = @deployments[key] ||= project.deployments.where(environment: key[1], release: key[2]).limit(2).to_a
    return unless candidates.size == 1
    deployment = candidates.first
    return if (deployment.deployed_at || deployment.created_at) > at
    { uuid: deployment.uuid, release: deployment.release, evidence: "exact_release", repository: deployment.repository_full_name }
  end

  def quote(value)
    "'#{value.to_s.gsub('\\') { '\\\\' }.gsub("'") { "\\'" }}'"
  end
end
