# frozen_string_literal: true

require "json"

module Logister
  class CliTracesQuery
    TRACE_LIMIT = 200
    RESPONSE_BYTES_LIMIT = 900.kilobytes
    CONTEXT_BYTES_LIMIT = 64.kilobytes
    CURSOR_PRECISION = 3
    POSTGRES_CURSOR_TIMESTAMP_SQL = "date_trunc('milliseconds', trace_spans.started_at)".freeze

    POSTGRES_BASE_PROJECTION_SQL = <<~SQL.squish.freeze
      trace_spans.uuid,
      LEFT(trace_spans.trace_id, 128) AS trace_id,
      LEFT(trace_spans.span_id, 128) AS span_id,
      LEFT(trace_spans.parent_span_id, 128) AS parent_span_id,
      LEFT(trace_spans.name, 4096) AS name,
      trace_spans.kind,
      LEFT(trace_spans.status, 32) AS status,
      trace_spans.duration_ms,
      date_trunc('milliseconds', trace_spans.started_at) AS started_at,
      trace_spans.ended_at
    SQL
    POSTGRES_SUMMARY_CONTEXT_SQL = <<~SQL.squish.freeze
      jsonb_strip_nulls(jsonb_build_object(
        'environment', LEFT(trace_spans.context->>'environment', 100),
        'release', LEFT(trace_spans.context->>'release', 200),
        'service', LEFT(trace_spans.context->>'service', 200),
        'route', LEFT(COALESCE(
          trace_spans.context->>'route',
          trace_spans.context->>'http.route',
          trace_spans.context->>'transaction_name'
        ), 512),
        'request_id', LEFT(COALESCE(
          trace_spans.context->>'request_id',
          trace_spans.context->>'requestId'
        ), 200)
      ))
    SQL

    ListResult = Data.define(:items, :read)
    TraceResult = Data.define(:items, :read, :truncated)

    class << self
      def list(project:, since:, to:, filters:, cursor:, limit:)
        read = ClickhouseReadRouter.call(
          project_ids: [ project.id ],
          signals: [ "span" ],
          from: since,
          to:,
          clickhouse: ->(client) { clickhouse_list(client:, project:, since:, to:, filters:, cursor:, limit:) },
          postgres: -> { postgres_list(project:, since:, to:, filters:, cursor:, limit:) }
        )
        ListResult.new(read.payload, read)
      end

      def trace(project:, trace_id:, since:, to:)
        read = ClickhouseReadRouter.call(
          project_ids: [ project.id ],
          signals: [ "span" ],
          from: since,
          to:,
          clickhouse: ->(client) { clickhouse_trace(client:, project:, trace_id:, since:, to:) },
          postgres: -> { postgres_trace(project:, trace_id:, since:, to:) }
        )
        items, response_truncated = bound_response(read.payload)
        context_truncated = items.any? { |item| item[:context_truncated] || item["context_truncated"] }
        TraceResult.new(items, read, response_truncated || context_truncated || read.payload.length > TRACE_LIMIT)
      end

      private

      def postgres_list(project:, since:, to:, filters:, cursor:, limit:)
        scope = project.trace_spans.where(started_at: since...to)
                       .where(kind: TraceSpan::ROOT_KINDS, parent_span_id: [ nil, "" ])
        scope = apply_postgres_filters(scope, project:, filters:)
        if cursor
          scope = scope.where(
            "(#{POSTGRES_CURSOR_TIMESTAMP_SQL}, trace_spans.uuid) < (?, ?::uuid)",
            millisecond_time(cursor[:timestamp]),
            cursor[:uuid]
          )
        end
        projected_postgres_scope(scope, include_context: false)
          .order(Arel.sql("#{POSTGRES_CURSOR_TIMESTAMP_SQL} DESC, trace_spans.uuid DESC"))
          .limit(limit + 1).map do |span|
          serialize_postgres_span(span, project:, include_context: false)
        end
      end

      def postgres_trace(project:, trace_id:, since:, to:)
        scope = project.trace_spans.where(trace_id:, started_at: since...to)
        projected_postgres_scope(scope, include_context: true)
          .order(started_at: :asc, uuid: :asc)
          .limit(TRACE_LIMIT + 1)
          .map { |span| serialize_postgres_span(span, project:, include_context: true) }
      end

      def apply_postgres_filters(scope, project:, filters:)
        scope = scope.where("COALESCE(NULLIF(context->>'environment', ''), 'production') = ?", filters[:environment]) if filters[:environment]
        scope = scope.where("context->>'release' = ?", filters[:release]) if filters[:release]
        if filters[:service]
          scope = scope.where("COALESCE(NULLIF(context->>'service', ''), ?) = ?", project.slug, filters[:service])
        end
        if filters[:operation]
          scope = scope.where(
            "COALESCE(NULLIF(context->>'route', ''), NULLIF(context->>'http.route', ''), NULLIF(context->>'transaction_name', ''), trace_spans.name) = ?",
            filters[:operation]
          )
        end
        if filters[:status]
          scope = filters[:status] == "unset" ? scope.where("COALESCE(trace_spans.status, '') IN ('', 'unset')") : scope.where(status: filters[:status])
        end
        scope = scope.where("duration_ms >= ?", filters[:min_duration_ms]) if filters[:min_duration_ms]
        if filters[:q]
          term = "%#{ActiveRecord::Base.sanitize_sql_like(filters[:q].downcase)}%"
          scope = scope.where(
            <<~SQL.squish,
              LOWER(trace_spans.name) LIKE :term
              OR LOWER(trace_spans.trace_id) LIKE :term
              OR LOWER(trace_spans.span_id) LIKE :term
              OR LOWER(COALESCE(trace_spans.context->>'route', trace_spans.context->>'http.route', '')) LIKE :term
            SQL
            term:
          )
        end
        scope
      end

      def clickhouse_list(client:, project:, since:, to:, filters:, cursor:, limit:)
        clauses = clickhouse_filters(project:, since:, to:, filters:)
        clauses << "is_root = 1"
        clauses << "kind IN ('server', 'browser')"
        if cursor
          clauses << <<~SQL.squish
            (started_at < parseDateTime64BestEffort(#{quote(millisecond_time(cursor[:timestamp]).iso8601(CURSOR_PRECISION))}, #{CURSOR_PRECISION})
              OR (started_at = parseDateTime64BestEffort(#{quote(millisecond_time(cursor[:timestamp]).iso8601(CURSOR_PRECISION))}, #{CURSOR_PRECISION})
                AND span_id < toUUID(#{quote(cursor[:uuid])})))
          SQL
        end
        rows = client.select_rows!(<<~SQL.squish)
          SELECT
            toString(span_id) AS uuid,
            leftUTF8(trace_id, 128) AS trace_id,
            leftUTF8(external_span_id, 128) AS external_span_id,
            leftUTF8(parent_span_id, 128) AS parent_span_id,
            leftUTF8(name, 4096) AS name,
            leftUTF8(route, 512) AS route,
            kind,
            status,
            duration_ms,
            started_at,
            ended_at,
            leftUTF8(environment, 100) AS environment,
            leftUTF8(release, 200) AS release,
            leftUTF8(service, 200) AS service,
            leftUTF8(request_id, 200) AS request_id
          FROM #{client.span_facts_table_name}
          WHERE #{clauses.join(' AND ')}
          ORDER BY started_at DESC, span_id DESC
          LIMIT #{limit + 1}
        SQL
        rows.map { |row| serialize_clickhouse_span(row, include_context: false) }
      end

      def clickhouse_trace(client:, project:, trace_id:, since:, to:)
        clauses = clickhouse_filters(project:, since:, to:, filters: {})
        clauses << "trace_id = #{quote(trace_id)}"
        rows = client.select_rows!(<<~SQL.squish)
          SELECT
            toString(span_id) AS uuid,
            leftUTF8(trace_id, 128) AS trace_id,
            leftUTF8(external_span_id, 128) AS external_span_id,
            leftUTF8(parent_span_id, 128) AS parent_span_id,
            leftUTF8(name, 4096) AS name,
            leftUTF8(route, 512) AS route,
            kind,
            status,
            duration_ms,
            started_at,
            ended_at,
            leftUTF8(environment, 100) AS environment,
            leftUTF8(release, 200) AS release,
            leftUTF8(service, 200) AS service,
            leftUTF8(request_id, 200) AS request_id,
            if(length(context_json) <= #{CONTEXT_BYTES_LIMIT}, context_json, '{}') AS context_json,
            length(context_json) > #{CONTEXT_BYTES_LIMIT} AS context_truncated
          FROM #{client.span_facts_table_name}
          WHERE #{clauses.join(' AND ')}
          ORDER BY started_at ASC, span_id ASC
          LIMIT #{TRACE_LIMIT + 1}
        SQL
        rows.map { |row| serialize_clickhouse_span(row, include_context: true) }
      end

      def clickhouse_filters(project:, since:, to:, filters:)
        clauses = [
          "project_id = #{project.id.to_i}",
          "started_at >= parseDateTime64BestEffort(#{quote(since.utc.iso8601(6))}, 6)",
          "started_at < parseDateTime64BestEffort(#{quote(to.utc.iso8601(6))}, 6)"
        ]
        clauses << "environment = #{quote(filters[:environment])}" if filters[:environment]
        clauses << "release = #{quote(filters[:release])}" if filters[:release]
        clauses << "service = #{quote(filters[:service])}" if filters[:service]
        clauses << "(route = #{quote(filters[:operation])} OR (empty(route) AND name = #{quote(filters[:operation])}))" if filters[:operation]
        if filters[:status]
          clauses << if filters[:status] == "unset"
            "status IN ('', 'unset')"
          else
            "status = #{quote(filters[:status])}"
          end
        end
        clauses << "duration_ms >= #{filters[:min_duration_ms].to_f}" if filters[:min_duration_ms]
        if filters[:q]
          query = quote("%#{escape_like(filters[:q].downcase)}%")
          clauses << "(lowerUTF8(name) LIKE #{query} OR lowerUTF8(trace_id) LIKE #{query} OR lowerUTF8(external_span_id) LIKE #{query} OR lowerUTF8(route) LIKE #{query})"
        end
        clauses
      end

      def serialize_postgres_span(span, project:, include_context:)
        context = span.context.is_a?(Hash) ? span.context : {}
        payload = {
          uuid: span.uuid,
          trace_id: span.trace_id,
          span_id: span.span_id,
          parent_span_id: span.parent_span_id,
          name: span.name,
          operation: span.route_name,
          kind: span.kind,
          status: normalized_status(span.status),
          duration_ms: span.duration_ms.to_f.round(3),
          started_at: millisecond_timestamp(span.started_at),
          ended_at: CliSerializer.timestamp(span.ended_at),
          environment: context["environment"].presence || context[:environment].presence || "production",
          release: context["release"].presence || context[:release].presence,
          service: context["service"].presence || context[:service].presence || project.slug,
          request_id: span.request_id
        }.compact
        payload[:context] = CliSerializer.redacted(context) if include_context
        if span.has_attribute?(:cli_context_truncated) && ActiveModel::Type::Boolean.new.cast(span[:cli_context_truncated])
          payload[:context_truncated] = true
        end
        payload
      end

      def serialize_clickhouse_span(row, include_context:)
        payload = {
          uuid: row["uuid"],
          trace_id: row["trace_id"],
          span_id: row["external_span_id"],
          parent_span_id: row["parent_span_id"].presence,
          name: row["name"],
          operation: row["route"].presence || row["name"],
          kind: row["kind"],
          status: normalized_status(row["status"]),
          duration_ms: row.fetch("duration_ms", 0).to_f.round(3),
          started_at: normalized_timestamp(row["started_at"]),
          ended_at: normalized_timestamp(row["ended_at"]),
          environment: row["environment"].presence || "production",
          release: row["release"].presence,
          service: row["service"].presence,
          request_id: row["request_id"].presence
        }.compact
        payload[:context] = CliSerializer.redacted(parse_context(row["context_json"])) if include_context
        payload[:context_truncated] = true if row.fetch("context_truncated", 0).to_i == 1
        payload
      end

      def projected_postgres_scope(scope, include_context:)
        context_sql = if include_context
          <<~SQL.squish
            CASE
              WHEN octet_length(trace_spans.context::text) <= #{CONTEXT_BYTES_LIMIT}
              THEN trace_spans.context
              ELSE #{POSTGRES_SUMMARY_CONTEXT_SQL}
            END
          SQL
        else
          POSTGRES_SUMMARY_CONTEXT_SQL
        end
        truncated_sql = include_context ? "octet_length(trace_spans.context::text) > #{CONTEXT_BYTES_LIMIT}" : "FALSE"
        scope.reselect(
          Arel.sql(POSTGRES_BASE_PROJECTION_SQL),
          Arel.sql("#{context_sql} AS context"),
          Arel.sql("#{truncated_sql} AS cli_context_truncated")
        )
      end

      def bound_response(items)
        bytes = 2
        bounded = []
        truncated = items.length > TRACE_LIMIT
        items.first(TRACE_LIMIT).each do |item|
          candidate = item
          item_bytes = JSON.generate(candidate).bytesize + 1
          if bytes + item_bytes > RESPONSE_BYTES_LIMIT && (candidate.key?(:context) || candidate.key?("context"))
            candidate = candidate.except(:context, "context").merge(context_truncated: true)
            item_bytes = JSON.generate(candidate).bytesize + 1
            truncated = true
          end
          if bytes + item_bytes > RESPONSE_BYTES_LIMIT
            truncated = true
            break
          end

          bounded << candidate
          bytes += item_bytes
        end
        [ bounded, truncated || bounded.length < items.length ]
      end

      def normalized_status(value)
        value.to_s.presence_in(%w[ok error]) || "unset"
      end

      def normalized_timestamp(value)
        return if value.blank?

        millisecond_timestamp(Time.zone.parse(value.to_s))
      rescue ArgumentError
        nil
      end

      def millisecond_timestamp(value)
        millisecond_time(value)&.iso8601(CURSOR_PRECISION)
      end

      def millisecond_time(value)
        time = value&.to_time&.utc
        return unless time

        Time.at(time.to_i, (time.nsec / 1_000_000) * 1_000, :microsecond).utc
      end

      def parse_context(value)
        parsed = JSON.parse(value.to_s)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def escape_like(value)
        value.to_s.gsub("\\", "\\\\").gsub("%", "\\%").gsub("_", "\\_")
      end

      def quote(value)
        escaped = value.to_s.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }
        "'#{escaped}'"
      end
    end
  end
end
