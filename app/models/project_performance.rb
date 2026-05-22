class ProjectPerformance
  REQUEST_LIMIT = 25
  SPAN_LOOKBACK_PADDING = 5.minutes

  SEGMENTS = [
    { key: "app", label: "App", color: "#2563eb" },
    { key: "db", label: "Database", color: "#8b5cf6" },
    { key: "render", label: "Render", color: "#059669" },
    { key: "http", label: "HTTP", color: "#d97706" },
    { key: "cache", label: "Cache", color: "#0f766e" },
    { key: "queue", label: "Queue", color: "#db2777" },
    { key: "resource", label: "Resources", color: "#64748b" },
    { key: "other", label: "Other", color: "#cbd5e1" }
  ].freeze

  CHILD_SEGMENT_KEYS = SEGMENTS.pluck(:key) - [ "app", "other" ]

  class << self
    def request_breakdown(project, since: 24.hours.ago, limit: REQUEST_LIMIT)
      clickhouse_payload = request_breakdown_from_clickhouse(project, since:, limit:)
      return clickhouse_payload if clickhouse_payload.present?

      roots = project.trace_spans.recent_roots(since, limit).to_a
      return transaction_breakdown(project, since:, limit:) if roots.empty?

      trace_ids = roots.map(&:trace_id).uniq
      root_ids = roots.map(&:id)
      window_start = [ roots.map(&:started_at).compact.min || since, since ].min - SPAN_LOOKBACK_PADDING
      window_end = [ roots.filter_map(&:ended_at).max || Time.current, Time.current ].max + SPAN_LOOKBACK_PADDING

      children_by_trace = project.trace_spans
                                 .where(trace_id: trace_ids, started_at: window_start..window_end)
                                 .where.not(id: root_ids)
                                 .select(:id, :trace_id, :span_id, :parent_span_id, :name, :kind, :status, :duration_ms, :started_at, :ended_at, :context)
                                 .group_by(&:trace_id)

      rows = roots.map { |root| row_from_root_span(root, children_by_trace.fetch(root.trace_id, [])) }

      payload(rows)
    end

    def segments
      SEGMENTS
    end

    private

    def request_breakdown_from_clickhouse(project, since:, limit:)
      client = Logister::ClickhouseClient.new
      return unless client.enabled?

      config = Rails.configuration.x.logister
      table = "#{config.clickhouse_database}.#{config.clickhouse_spans_table}"
      since_literal = quote_clickhouse_time(since)
      root_rows = client.select_rows!(<<~SQL.squish)
        SELECT
          span_id,
          trace_id,
          external_span_id,
          name,
          route,
          kind,
          status,
          duration_ms,
          started_at,
          request_id
        FROM #{table}
        WHERE project_id = #{project.id.to_i}
          AND started_at >= parseDateTime64BestEffort(#{since_literal}, 3)
          AND kind IN ('server', 'browser')
          AND parent_span_id = ''
        ORDER BY duration_ms DESC, started_at DESC
        LIMIT #{limit.to_i.clamp(1, REQUEST_LIMIT)}
      SQL
      return if root_rows.empty?

      trace_ids = root_rows.map { |row| row["trace_id"].to_s }.reject(&:blank?).uniq
      child_rows = if trace_ids.any?
        client.select_rows!(<<~SQL.squish)
          SELECT
            trace_id,
            kind,
            sum(duration_ms) AS duration_ms,
            count() AS child_count
          FROM #{table}
          WHERE project_id = #{project.id.to_i}
            AND started_at >= parseDateTime64BestEffort(#{since_literal}, 3)
            AND trace_id IN (#{trace_ids.map { |trace_id| quote_clickhouse(trace_id) }.join(", ")})
            AND parent_span_id != ''
          GROUP BY trace_id, kind
        SQL
      else
        []
      end

      child_by_trace = child_rows.group_by { |row| row["trace_id"].to_s }
      rows = root_rows.map { |row| row_from_clickhouse_root(row, child_by_trace.fetch(row["trace_id"].to_s, [])) }

      payload(rows)
    rescue StandardError => e
      Rails.logger.warn("clickhouse request breakdown failed: #{e.class} #{e.message}")
      nil
    end

    def row_from_clickhouse_root(root, child_rows)
      segment_ms = empty_segment_hash
      child_count = 0
      child_rows.each do |row|
        key = segment_key(row["kind"])
        segment_ms[key] += numeric(row["duration_ms"]) if CHILD_SEGMENT_KEYS.include?(key)
        child_count += row["child_count"].to_i
      end

      duration = numeric(root["duration_ms"])
      child_total = segment_ms.values.sum
      segment_ms["app"] = [ duration - child_total, 0.0 ].max
      segment_ms["other"] = [ duration - segment_ms.values.sum, 0.0 ].max

      {
        id: root["span_id"],
        source: "span",
        label: root["route"].presence || root["name"].presence || "request",
        name: root["name"],
        started_at: root["started_at"],
        duration_ms: rounded(duration),
        trace_id: root["trace_id"],
        request_id: root["request_id"],
        status: root["status"],
        segments: rounded_segments(segment_ms),
        child_count: child_count
      }
    end

    def row_from_root_span(root, children)
      segment_ms = empty_segment_hash
      children.each do |child|
        key = segment_key(child.kind)
        segment_ms[key] += child.duration_ms.to_f if CHILD_SEGMENT_KEYS.include?(key)
      end

      child_total = segment_ms.values.sum
      segment_ms["app"] = [ root.duration_ms.to_f - child_total, 0.0 ].max
      segment_ms["other"] = [ root.duration_ms.to_f - segment_ms.values.sum, 0.0 ].max

      {
        id: root.uuid,
        source: "span",
        label: root.route_name,
        name: root.name,
        started_at: root.started_at&.utc&.iso8601,
        duration_ms: rounded(root.duration_ms),
        trace_id: root.trace_id,
        request_id: root.request_id,
        status: root.status,
        segments: rounded_segments(segment_ms),
        child_count: children.size
      }
    end

    def transaction_breakdown(project, since:, limit:)
      events = project.ingest_events
                      .recent_transactions(since, limit)
                      .select(:id, :uuid, :message, :level, :occurred_at, :context)
                      .to_a

      rows = events.map { |event| row_from_transaction(event) }
      payload(rows)
    end

    def row_from_transaction(event)
      context = event.context.is_a?(Hash) ? event.context : {}
      total = IngestEvent.duration_ms(event)
      segment_ms = empty_segment_hash
      explicit = normalized_timing_breakdown(context)

      if explicit.any?
        explicit.each { |key, value| segment_ms[segment_key(key)] += numeric(value) }
      else
        performance = context["performance"] || context[:performance] || {}
        segment_ms["db"] = numeric(performance["dbRuntimeMs"] || performance[:dbRuntimeMs] || performance["db_runtime_ms"] || performance[:db_runtime_ms])
        segment_ms["render"] = numeric(performance["viewRuntimeMs"] || performance[:viewRuntimeMs] || performance["view_runtime_ms"] || performance[:view_runtime_ms])
        segment_ms["http"] = dependency_duration_ms(context)
      end

      measured = segment_ms.values.sum
      segment_ms["app"] = [ total - measured, 0.0 ].max
      segment_ms["other"] = [ total - segment_ms.values.sum, 0.0 ].max

      {
        id: event.uuid,
        source: "transaction",
        label: IngestEvent.transaction_name(event).presence || event.message,
        name: event.message,
        started_at: event.occurred_at&.utc&.iso8601,
        duration_ms: rounded(total),
        trace_id: IngestEvent.trace_id(event),
        request_id: IngestEvent.request_id(event),
        status: context["status"] || context[:status],
        segments: rounded_segments(segment_ms),
        child_count: 0
      }
    end

    def payload(rows)
      {
        segments: SEGMENTS,
        requests: rows.sort_by { |row| -row[:duration_ms].to_f }.first(REQUEST_LIMIT),
        generated_at: Time.current.utc.iso8601
      }
    end

    def normalized_timing_breakdown(context)
      raw = context["timing_breakdown"] || context[:timing_breakdown] || context["timings"] || context[:timings]
      return {} unless raw.is_a?(Hash)

      raw
    end

    def dependency_duration_ms(context)
      dependencies = context["dependencyCalls"] || context[:dependencyCalls] || context["dependencies"] || context[:dependencies]
      Array(dependencies).sum do |dependency|
        next 0.0 unless dependency.is_a?(Hash)

        numeric(dependency["durationMs"] || dependency[:durationMs] || dependency["duration_ms"] || dependency[:duration_ms])
      end
    end

    def empty_segment_hash
      SEGMENTS.index_with { 0.0 }.transform_keys { |segment| segment.fetch(:key) }
    end

    def segment_key(value)
      case value.to_s.underscore
      when "database", "sql" then "db"
      when "external", "client" then "http"
      when "view", "template" then "render"
      when "browser" then "app"
      else
        SEGMENTS.any? { |segment| segment.fetch(:key) == value.to_s } ? value.to_s : "other"
      end
    end

    def numeric(value)
      value.to_f.positive? ? value.to_f : 0.0
    end

    def rounded(value)
      value.to_f.round(2)
    end

    def rounded_segments(segments)
      segments.transform_values { |value| rounded(value) }
    end

    def quote_clickhouse(value)
      "'#{value.to_s.gsub("'", "''")}'"
    end

    def quote_clickhouse_time(value)
      quote_clickhouse(value.utc.iso8601(3))
    end
  end
end
