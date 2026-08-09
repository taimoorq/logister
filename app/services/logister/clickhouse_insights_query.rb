# frozen_string_literal: true

require "json"

module Logister
  class ClickhouseInsightsQuery
    BUCKET_FUNCTIONS = {
      "minute" => "toStartOfMinute",
      "hour" => "toStartOfHour",
      "day" => "toStartOfDay"
    }.freeze

    def initialize(project:, since:, to:, bucket:, environment: nil, release: nil,
                   attribute_filters: {}, custom_metric_names: [], client:)
      @project = project
      @since = since.to_time.utc
      @to = to.to_time.utc
      @bucket = bucket.to_s
      @environment = environment.to_s.presence
      @release = release.to_s.presence
      @attribute_filters = attribute_filters.to_h
      @custom_metric_names = Array(custom_metric_names).map(&:to_s).reject(&:blank?).uniq
      @client = client
    end

    def call
      rows = normalize_standard_rows(@client.select_rows!(dashboard_query))
      summary_payload = summary(rows)
      rows.each { |row| row.delete("latest_event_at") }
      {
        summary: summary_payload,
        standard_bucket_rows: rows,
        custom_metric_rows: custom_metric_analytics_rows
      }
    end

    def custom_metric_rows(limit: ProjectInsights::MAX_CUSTOM_METRICS)
      @client.select_rows!(<<~SQL.squish)
        SELECT
          metric_name,
          count() AS event_count,
          countIf(metric_value IS NOT NULL) AS numeric_count
        FROM #{@client.event_facts_table_name}
        WHERE #{base_filters(event_type: "metric").join(" AND ")}
          AND metric_name != ''
          AND metric_name != 'db.query'
        GROUP BY metric_name
        ORDER BY event_count DESC, metric_name ASC
        LIMIT #{limit.to_i.clamp(1, ProjectInsights::MAX_CUSTOM_METRICS)}
      SQL
    end

    def filter_rows(attribute_sample_limit: ProjectInsights::ATTRIBUTE_CATALOG_SAMPLE_LIMIT)
      {
        environments: @client.select_rows!(dimension_query("if(empty(environment), 'unknown', environment)", "name")),
        releases: @client.select_rows!(dimension_query("release", "name", extra_filter: "release != ''")),
        attributes: @client.select_rows!(attribute_query(attribute_sample_limit:))
      }
    end

    private

    def custom_metric_analytics_rows
      return [] if @custom_metric_names.empty?

      function = BUCKET_FUNCTIONS.fetch(@bucket)
      rows = @client.select_rows!(<<~SQL.squish)
        SELECT
          #{function}(occurred_at) AS bucket_time,
          metric_name,
          count() AS event_count,
          countIf(metric_value IS NOT NULL) AS numeric_count,
          avgIf(metric_value, metric_value IS NOT NULL) AS value_avg
        FROM #{@client.event_facts_table_name}
        WHERE #{base_filters(event_type: "metric").join(" AND ")}
          AND metric_name IN (#{@custom_metric_names.map { |name| quote(name) }.join(", ")})
        GROUP BY bucket_time, metric_name
        ORDER BY bucket_time, metric_name
      SQL
      rows.map do |row|
        {
          "bucket_time" => normalized_time(row["bucket_time"]),
          "metric_name" => row.fetch("metric_name").to_s,
          "event_count" => row.fetch("event_count", 0).to_i,
          "numeric_count" => row.fetch("numeric_count", 0).to_i,
          "value_avg" => row.fetch("value_avg", 0).to_f
        }
      end
    end

    def normalize_standard_rows(rows)
      integer_columns = %w[
        events_total errors_count activity_count logs_count metrics_count check_ins_count
        transactions_count transactions_duration_count db_query_count db_query_duration_count
      ]
      float_columns = %w[transactions_avg transactions_p95 db_query_avg db_query_p95]
      rows.map do |row|
        normalized = row.stringify_keys
        normalized["bucket_time"] = normalized_time(normalized["bucket_time"])
        normalized["latest_event_at"] = normalized_time(normalized["latest_event_at"])
        integer_columns.each { |column| normalized[column] = normalized.fetch(column, 0).to_i }
        float_columns.each { |column| normalized[column] = normalized.fetch(column, 0).to_f.round(6) }
        normalized
      end
    end

    def normalized_time(value)
      parse_time(value)&.iso8601
    end

    def dashboard_query
      function = BUCKET_FUNCTIONS.fetch(@bucket) { raise ArgumentError, "Unsupported ClickHouse insights bucket: #{@bucket.inspect}" }
      <<~SQL.squish
        SELECT
          #{function}(occurred_at) AS bucket_time,
          count() AS events_total,
          countIf(event_type = 'error') AS errors_count,
          countIf(event_type != 'error') AS activity_count,
          countIf(event_type = 'log') AS logs_count,
          countIf(event_type = 'metric') AS metrics_count,
          countIf(event_type = 'check_in') AS check_ins_count,
          countIf(event_type = 'transaction') AS transactions_count,
          countIf(event_type = 'transaction' AND duration_ms IS NOT NULL) AS transactions_duration_count,
          avgIf(duration_ms, event_type = 'transaction' AND duration_ms IS NOT NULL) AS transactions_avg,
          quantileTDigestIf(0.95)(duration_ms, event_type = 'transaction' AND duration_ms IS NOT NULL) AS transactions_p95,
          countIf(event_type = 'metric' AND metric_name = 'db.query') AS db_query_count,
          countIf(event_type = 'metric' AND metric_name = 'db.query' AND duration_ms IS NOT NULL) AS db_query_duration_count,
          avgIf(duration_ms, event_type = 'metric' AND metric_name = 'db.query' AND duration_ms IS NOT NULL) AS db_query_avg,
          quantileTDigestIf(0.95)(duration_ms, event_type = 'metric' AND metric_name = 'db.query' AND duration_ms IS NOT NULL) AS db_query_p95,
          max(occurred_at) AS latest_event_at
        FROM #{@client.event_facts_table_name}
        WHERE #{base_filters.join(" AND ")}
        GROUP BY bucket_time
        ORDER BY bucket_time
      SQL
    end

    def dimension_query(expression, alias_name, extra_filter: nil)
      filters = base_filters
      filters << extra_filter if extra_filter
      <<~SQL.squish
        SELECT #{expression} AS #{alias_name}, count() AS count
        FROM #{@client.event_facts_table_name}
        WHERE #{filters.join(" AND ")}
        GROUP BY #{alias_name}
        ORDER BY count DESC, #{alias_name} ASC
        LIMIT 20
      SQL
    end

    def attribute_query(attribute_sample_limit:)
      <<~SQL.squish
        SELECT
          attribute.1 AS attribute_key,
          attribute.2 AS attribute_raw_value,
          toString(JSONType(attribute.2)) AS attribute_type,
          count() AS count
        FROM
        (
          SELECT context_json
          FROM #{@client.event_facts_table_name}
          WHERE #{base_filters.join(" AND ")}
          ORDER BY occurred_at DESC
          LIMIT #{attribute_sample_limit.to_i.clamp(1, ProjectInsights::ATTRIBUTE_CATALOG_SAMPLE_LIMIT)}
        ) AS sampled_events
        ARRAY JOIN JSONExtractKeysAndValuesRaw(context_json) AS attribute
        WHERE attribute.2 != ''
          AND JSONType(attribute.2) IN ('String', 'Int64', 'UInt64', 'Float64', 'Bool')
        GROUP BY attribute_key, attribute_raw_value, attribute_type
        ORDER BY count DESC
        LIMIT #{ProjectInsights::MAX_ATTRIBUTE_KEYS * ProjectInsights::MAX_ATTRIBUTE_VALUES * 3}
      SQL
    end

    def base_filters(event_type: nil)
      filters = [
        "project_id = #{@project.id.to_i}",
        "occurred_at >= parseDateTime64BestEffort(#{quote(@since.iso8601(3))}, 3)",
        "occurred_at < parseDateTime64BestEffort(#{quote(@to.iso8601(3))}, 3)"
      ]
      filters << "event_type = #{quote(event_type)}" if event_type
      filters << "environment = #{quote(@environment)}" if @environment
      filters << "release = #{quote(@release)}" if @release
      @attribute_filters.each do |key, filter|
        filters << "JSONExtractRaw(context_json, #{quote(key)}) = #{quote(attribute_raw_value(filter))}"
      end
      filters
    end

    def attribute_raw_value(filter)
      value = filter.fetch(:value)
      typed = case filter.fetch(:type).to_s
      when "number"
        value.to_s.match?(/\A-?\d+\z/) ? value.to_i : Float(value)
      when "boolean"
        value.to_s == "true"
      else
        value.to_s
      end
      JSON.generate(typed)
    rescue ArgumentError, TypeError
      JSON.generate(value.to_s)
    end

    def summary(rows)
      totals = rows.each_with_object(Hash.new(0)) do |row, values|
        %w[events_total errors_count activity_count logs_count metrics_count transactions_count check_ins_count].each do |key|
          values[key] += row.fetch(key, 0).to_i
        end
      end
      latest = rows.filter_map { |row| parse_time(row["latest_event_at"]) }.max
      {
        events: totals["events_total"],
        errors: totals["errors_count"],
        activity: totals["activity_count"],
        logs: totals["logs_count"],
        metrics: totals["metrics_count"],
        transactions: totals["transactions_count"],
        check_ins: totals["check_ins_count"],
        latest_event_at: latest&.iso8601
      }
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)&.utc
    rescue ArgumentError
      nil
    end

    def quote(value)
      escaped = value.to_s.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }
      "'#{escaped}'"
    end
  end
end
