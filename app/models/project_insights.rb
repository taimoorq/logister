# frozen_string_literal: true

class ProjectInsights
  DEFAULT_WINDOW = "24h"
  MAX_CUSTOM_METRICS = 12
  MAX_SELECTED_METRICS = 8
  MAX_FILTER_LENGTH = 80

  WINDOW_OPTIONS = {
    "1h" => { label: "1h", duration: 1.hour, bucket: "minute" },
    "6h" => { label: "6h", duration: 6.hours, bucket: "hour" },
    "24h" => { label: "24h", duration: 24.hours, bucket: "hour" },
    "7d" => { label: "7d", duration: 7.days, bucket: "day" }
  }.freeze

  EVENT_TYPE_LABELS = {
    "error" => "Errors",
    "log" => "Logs",
    "metric" => "Metrics",
    "transaction" => "Transactions",
    "check_in" => "Check-ins"
  }.freeze

  EVENT_TYPE_COLORS = {
    "error" => "#ef4444",
    "log" => "#64748b",
    "metric" => "#8b5cf6",
    "transaction" => "#059669",
    "check_in" => "#2563eb"
  }.freeze

  BASE_METRICS = {
    "events.total" => {
      key: "events.total",
      label: "Total events",
      description: "Every activity, error, metric, transaction, and check-in event.",
      unit: "count",
      kind: "count",
      source: "Activity"
    },
    "errors.count" => {
      key: "errors.count",
      label: "Errors",
      description: "Error events captured by the project.",
      unit: "count",
      kind: "count",
      source: "Inbox"
    },
    "activity.count" => {
      key: "activity.count",
      label: "Activity events",
      description: "Non-error events flowing into Activity.",
      unit: "count",
      kind: "count",
      source: "Activity"
    },
    "logs.count" => {
      key: "logs.count",
      label: "Logs",
      description: "Log events captured by the project.",
      unit: "count",
      kind: "count",
      source: "Activity"
    },
    "check_ins.count" => {
      key: "check_ins.count",
      label: "Check-ins",
      description: "Monitor check-in events captured by the project.",
      unit: "count",
      kind: "count",
      source: "Activity"
    },
    "transactions.count" => {
      key: "transactions.count",
      label: "Transactions",
      description: "Transaction events from Performance.",
      unit: "count",
      kind: "count",
      source: "Performance"
    },
    "transactions.avg" => {
      key: "transactions.avg",
      label: "Avg transaction duration",
      description: "Average transaction duration from Performance.",
      unit: "ms",
      kind: "duration",
      source: "Performance"
    },
    "transactions.p95" => {
      key: "transactions.p95",
      label: "P95 transaction duration",
      description: "95th percentile transaction duration from Performance.",
      unit: "ms",
      kind: "duration",
      source: "Performance"
    },
    "db.query.count" => {
      key: "db.query.count",
      label: "DB queries",
      description: "Database query metric events.",
      unit: "count",
      kind: "count",
      source: "Performance"
    },
    "db.query.avg" => {
      key: "db.query.avg",
      label: "Avg DB query duration",
      description: "Average database query duration.",
      unit: "ms",
      kind: "duration",
      source: "Performance"
    },
    "db.query.p95" => {
      key: "db.query.p95",
      label: "P95 DB query duration",
      description: "95th percentile database query duration.",
      unit: "ms",
      kind: "duration",
      source: "Performance"
    }
  }.freeze

  DEFAULT_METRIC_KEYS = %w[
    events.total
    errors.count
    transactions.p95
    db.query.avg
  ].freeze

  class << self
    def window_options
      WINDOW_OPTIONS.map { |key, config| { key: key, label: config[:label] } }
    end

    def event_type_catalog
      EVENT_TYPE_LABELS.map do |key, label|
        { key: key, label: label, color: EVENT_TYPE_COLORS.fetch(key) }
      end
    end

    def default_metric_keys
      DEFAULT_METRIC_KEYS
    end

    def normalize_window(value)
      key = value.to_s
      WINDOW_OPTIONS.key?(key) ? key : DEFAULT_WINDOW
    end

    def catalog_for(project, window: DEFAULT_WINDOW)
      window_key = normalize_window(window)
      since = since_for(window_key)
      base_metrics = BASE_METRICS.values.map(&:dup)

      base_metrics + custom_metric_catalog(project, since)
    end

    def filter_options(project, window: DEFAULT_WINDOW)
      {
        environments: environments_for(project, window: window),
        releases: releases_for(project, window: window)
      }
    end

    def dashboard_for(project, window:, metrics:, environment:, release:)
      window_key = normalize_window(window)
      since = since_for(window_key)
      catalog = catalog_for(project, window: window_key)
      selected_metrics = normalize_metric_keys(metrics, catalog)
      filters = {
        environment: normalize_filter(environment),
        release: normalize_filter(release)
      }
      scope = events_scope(project, since: since, environment: filters[:environment], release: filters[:release])
      bucket = WINDOW_OPTIONS.fetch(window_key).fetch(:bucket)
      buckets = buckets_for(since, bucket)

      {
        generated_at: Time.current.utc.iso8601,
        window: window_key,
        bucket: bucket,
        buckets: buckets.map { |bucket_time| bucket_time.utc.iso8601 },
        filters: filters.compact,
        summary: summary_for(scope),
        event_type_catalog: event_type_catalog,
        event_timeline: event_timeline(scope, buckets, bucket),
        event_types: event_type_breakdown(scope),
        metric_catalog: catalog,
        selected_metrics: selected_metrics,
        metric_series: metric_series(scope, selected_metrics, catalog, buckets, bucket),
        environments: environments_for(project, window: window_key),
        releases: releases_for(project, window: window_key),
        recent_events: recent_events(scope)
      }
    end

    def environments_for(project, window: DEFAULT_WINDOW)
      since = since_for(normalize_window(window))
      counts = project.ingest_events
                      .where("occurred_at >= ?", since)
                      .group(Arel.sql(environment_sql))
                      .count

      ranked_filter_options(counts)
    end

    def releases_for(project, window: DEFAULT_WINDOW)
      since = since_for(normalize_window(window))
      counts = project.ingest_events
                      .where("occurred_at >= ?", since)
                      .where("COALESCE(context->>'release', '') <> ''")
                      .group(Arel.sql("context->>'release'"))
                      .count

      ranked_filter_options(counts)
    end

    private

    def custom_metric_catalog(project, since)
      counts = project.ingest_events
                      .where(event_type: IngestEvent.event_types.fetch("metric"))
                      .where.not(message: "db.query")
                      .where("occurred_at >= ?", since)
                      .group(:message)
                      .order(Arel.sql("COUNT(*) DESC"))
                      .limit(MAX_CUSTOM_METRICS)
                      .count

      counts.filter_map do |message, count|
        name = message.to_s.strip
        next if name.blank?

        {
          key: custom_metric_key(name),
          label: name.truncate(64),
          description: "Metric event count for #{name.truncate(80)}.",
          unit: "count",
          kind: "count",
          source: "Metrics",
          events: count
        }
      end
    end

    def normalize_metric_keys(metrics, catalog)
      available_keys = catalog.map { |metric| metric.fetch(:key) }
      requested = Array(metrics).map(&:to_s)
                                .map(&:strip)
                                .select { |metric| available_keys.include?(metric) }
                                .uniq
                                .first(MAX_SELECTED_METRICS)

      return requested if requested.present?

      DEFAULT_METRIC_KEYS.select { |metric| available_keys.include?(metric) }
    end

    def normalize_filter(value)
      value.to_s.strip.first(MAX_FILTER_LENGTH).presence
    end

    def since_for(window)
      WINDOW_OPTIONS.fetch(window).fetch(:duration).ago
    end

    def events_scope(project, since:, environment:, release:)
      scope = project.ingest_events.where("occurred_at >= ?", since)
      scope = scope.where("#{environment_sql} = ?", environment) if environment.present?
      scope = scope.where("context->>'release' = ?", release) if release.present?
      scope
    end

    def environment_sql
      "COALESCE(NULLIF(context->>'environment', ''), 'unknown')"
    end

    def summary_for(scope)
      counts = normalize_event_counts(scope.group(:event_type).count)
      total_events = counts.values.sum
      latest_event_at = scope.maximum(:occurred_at)

      {
        events: total_events,
        errors: counts.fetch("error", 0),
        activity: total_events - counts.fetch("error", 0),
        logs: counts.fetch("log", 0),
        metrics: counts.fetch("metric", 0),
        transactions: counts.fetch("transaction", 0),
        check_ins: counts.fetch("check_in", 0),
        latest_event_at: latest_event_at&.utc&.iso8601
      }
    end

    def event_type_breakdown(scope)
      counts = normalize_event_counts(scope.group(:event_type).count)

      EVENT_TYPE_LABELS.map do |key, label|
        { key: key, label: label, count: counts.fetch(key, 0), color: EVENT_TYPE_COLORS.fetch(key) }
      end
    end

    def event_timeline(scope, buckets, bucket)
      bucket_expr = bucket_expression(bucket)
      counts = scope.group(Arel.sql(bucket_expr), :event_type).count
      rows = buckets.index_by { |bucket_time| bucket_time.utc.iso8601 }.transform_values do |bucket_time|
        row = { timestamp: bucket_time.utc.iso8601 }
        EVENT_TYPE_LABELS.keys.each { |event_type| row[event_type] = 0 }
        row
      end

      counts.each do |(bucket_time, event_type), count|
        timestamp = bucket_timestamp(bucket_time, bucket)
        event_type_name = normalize_event_type(event_type)
        rows[timestamp][event_type_name] = count if rows.key?(timestamp) && event_type_name.present?
      end

      rows.values
    end

    def metric_series(scope, metric_keys, catalog, buckets, bucket)
      definitions = catalog.index_by { |metric| metric.fetch(:key) }

      metric_keys.filter_map do |metric_key|
        definition = definitions[metric_key]
        next if definition.blank?

        {
          key: metric_key,
          label: definition.fetch(:label),
          unit: definition.fetch(:unit),
          kind: definition.fetch(:kind),
          source: definition.fetch(:source),
          data: metric_data(scope, metric_key, buckets, bucket)
        }
      end
    end

    def metric_data(scope, metric_key, buckets, bucket)
      case metric_key
      when "events.total"
        count_data(scope, buckets, bucket)
      when "errors.count"
        count_data(scope.where(event_type: IngestEvent.event_types.fetch("error")), buckets, bucket)
      when "activity.count"
        count_data(scope.where.not(event_type: IngestEvent.event_types.fetch("error")), buckets, bucket)
      when "logs.count"
        count_data(scope.where(event_type: IngestEvent.event_types.fetch("log")), buckets, bucket)
      when "check_ins.count"
        count_data(scope.where(event_type: IngestEvent.event_types.fetch("check_in")), buckets, bucket)
      when "transactions.count"
        count_data(scope.where(event_type: IngestEvent.event_types.fetch("transaction")), buckets, bucket)
      when "transactions.avg"
        duration_data(scope.where(event_type: IngestEvent.event_types.fetch("transaction")), buckets, bucket, aggregate: :avg)
      when "transactions.p95"
        duration_data(scope.where(event_type: IngestEvent.event_types.fetch("transaction")), buckets, bucket, aggregate: :p95)
      when "db.query.count"
        count_data(db_query_scope(scope), buckets, bucket)
      when "db.query.avg"
        duration_data(db_query_scope(scope), buckets, bucket, aggregate: :avg)
      when "db.query.p95"
        duration_data(db_query_scope(scope), buckets, bucket, aggregate: :p95)
      else
        if metric_key.start_with?("metric:")
          count_data(scope.where(event_type: IngestEvent.event_types.fetch("metric"), message: custom_metric_name(metric_key)), buckets, bucket)
        else
          empty_data(buckets)
        end
      end
    end

    def db_query_scope(scope)
      scope.where(event_type: IngestEvent.event_types.fetch("metric"), message: "db.query")
    end

    def count_data(scope, buckets, bucket)
      counts = scope.group(Arel.sql(bucket_expression(bucket))).count
      values = counts.transform_keys { |bucket_time| bucket_timestamp(bucket_time, bucket) }

      buckets.map do |bucket_time|
        { timestamp: bucket_time.utc.iso8601, value: values.fetch(bucket_time.utc.iso8601, 0) }
      end
    end

    def duration_data(scope, buckets, bucket, aggregate:)
      values = duration_values(scope, bucket, aggregate)

      buckets.map do |bucket_time|
        value = values.fetch(bucket_time.utc.iso8601, 0)
        { timestamp: bucket_time.utc.iso8601, value: value.to_f.round(2) }
      end
    end

    def duration_values(scope, bucket, aggregate)
      inner_sql = scope.select(:occurred_at, :context).to_sql
      bucket_expr = bucket_expression(bucket, table_name: "scoped_events")
      aggregate_sql = aggregate == :p95 ? "percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms)" : "AVG(duration_ms)"
      duration_sql = duration_value_sql
      sql = <<~SQL.squish
        SELECT bucket, #{aggregate_sql} AS value
        FROM (
          SELECT #{bucket_expr} AS bucket, #{duration_sql} AS duration_ms
          FROM (#{inner_sql}) scoped_events
        ) duration_rows
        WHERE duration_ms IS NOT NULL
        GROUP BY bucket
      SQL

      ApplicationRecord.connection.exec_query(sql).each_with_object({}) do |row, values|
        values[bucket_timestamp(row.fetch("bucket"), bucket)] = row.fetch("value").to_f
      end
    end

    def duration_value_sql
      raw_duration = "COALESCE(scoped_events.context->>'duration_ms', scoped_events.context->>'durationMs')"

      "CASE WHEN #{raw_duration} ~ '^-?[0-9]+(\\.[0-9]+)?$' THEN #{raw_duration}::double precision ELSE NULL END"
    end

    def empty_data(buckets)
      buckets.map { |bucket_time| { timestamp: bucket_time.utc.iso8601, value: 0 } }
    end

    def buckets_for(since, bucket)
      step = bucket_step(bucket)
      current = floor_time(since, bucket)
      last = floor_time(Time.current, bucket)
      buckets = []

      while current <= last
        buckets << current
        current += step
      end

      buckets
    end

    def bucket_step(bucket)
      case bucket
      when "minute" then 1.minute
      when "hour" then 1.hour
      else 1.day
      end
    end

    def floor_time(time, bucket)
      time = time.in_time_zone

      case bucket
      when "minute"
        time.change(sec: 0)
      when "hour"
        time.change(min: 0, sec: 0)
      else
        time.beginning_of_day
      end
    end

    def bucket_expression(bucket, table_name: "ingest_events")
      "date_trunc('#{bucket}', #{table_name}.occurred_at)"
    end

    def bucket_timestamp(value, bucket)
      floor_time(value.to_time.utc, bucket).utc.iso8601
    end

    def normalize_event_counts(counts)
      counts.each_with_object({}) do |(event_type, count), normalized|
        key = normalize_event_type(event_type)
        normalized[key] = count if key.present?
      end
    end

    def normalize_event_type(value)
      return value if value.is_a?(String) && IngestEvent.event_types.key?(value)

      IngestEvent.event_types.key(value.to_i)
    end

    def recent_events(scope)
      scope.order(occurred_at: :desc)
           .limit(12)
           .map do |event|
        context = event.context || {}
        {
          uuid: event.uuid,
          event_type: event.event_type,
          label: EVENT_TYPE_LABELS.fetch(event.event_type, event.event_type.titleize),
          message: event.message,
          level: event.level,
          occurred_at: event.occurred_at.utc.iso8601,
          environment: context["environment"].presence || "unknown",
          release: context["release"].presence,
          duration_ms: duration_value(context)
        }
      end
    end

    def duration_value(context)
      value = context["duration_ms"] || context["durationMs"]
      return nil if value.blank?

      Float(value).round(2)
    rescue ArgumentError, TypeError
      nil
    end

    def ranked_filter_options(counts)
      counts.sort_by { |name, count| [-count, name.to_s] }
            .first(20)
            .map { |name, count| { name: name.presence || "unknown", count: count } }
    end

    def custom_metric_key(name)
      "metric:#{name}"
    end

    def custom_metric_name(metric_key)
      metric_key.delete_prefix("metric:")
    end
  end
end
