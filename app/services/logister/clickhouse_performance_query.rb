# frozen_string_literal: true

module Logister
  class ClickhousePerformanceQuery
    def initialize(project:, since:, to:, limit:, client:)
      @project = project
      @since = since.to_time.utc
      @to = to.to_time.utc
      @limit = limit.to_i.clamp(1, ProjectPerformance::REQUEST_LIMIT)
      @client = client
    end

    def call
      roots = @client.select_rows!(root_query)
      return { root_rows: [], child_rows: [], transaction_rows: @client.select_rows!(transaction_query) } if roots.empty?

      trace_ids = roots.map { |row| row.fetch("trace_id", "").to_s }.reject(&:blank?).uniq
      children = trace_ids.empty? ? [] : @client.select_rows!(child_query(trace_ids))
      { root_rows: roots, child_rows: children, transaction_rows: [] }
    end

    private

    def root_query
      <<~SQL.squish
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
        FROM #{@client.span_facts_table_name}
        WHERE project_id = #{@project.id.to_i}
          AND started_at >= parseDateTime64BestEffort(#{quote(@since.iso8601(3))}, 3)
          AND started_at < parseDateTime64BestEffort(#{quote(@to.iso8601(3))}, 3)
          AND is_root = 1
          AND kind IN ('server', 'browser')
        ORDER BY duration_ms DESC, started_at DESC
        LIMIT #{@limit}
      SQL
    end

    def child_query(trace_ids)
      <<~SQL.squish
        SELECT
          trace_id,
          kind,
          sum(duration_ms) AS duration_ms,
          count() AS child_count
        FROM #{@client.span_facts_table_name}
        WHERE project_id = #{@project.id.to_i}
          AND started_at >= parseDateTime64BestEffort(#{quote(@since.iso8601(3))}, 3)
          AND started_at < parseDateTime64BestEffort(#{quote(@to.iso8601(3))}, 3)
          AND trace_id IN (#{trace_ids.map { |trace_id| quote(trace_id) }.join(", ")})
          AND is_root = 0
        GROUP BY trace_id, kind
      SQL
    end

    def transaction_query
      <<~SQL.squish
        SELECT
          event_id,
          message,
          level,
          occurred_at,
          duration_ms,
          transaction_name,
          transaction_status,
          trace_id,
          request_id,
          context_json
        FROM #{@client.event_facts_table_name}
        WHERE project_id = #{@project.id.to_i}
          AND event_type = 'transaction'
          AND occurred_at >= parseDateTime64BestEffort(#{quote(@since.iso8601(3))}, 3)
          AND occurred_at < parseDateTime64BestEffort(#{quote(@to.iso8601(3))}, 3)
        ORDER BY duration_ms DESC, occurred_at DESC
        LIMIT #{@limit}
      SQL
    end

    def quote(value)
      escaped = value.to_s.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }
      "'#{escaped}'"
    end
  end
end
