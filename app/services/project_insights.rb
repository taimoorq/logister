# frozen_string_literal: true

class ProjectInsights
  DEFAULT_WINDOW = "24h"
  MAX_CUSTOM_METRICS = 12
  MAX_SELECTED_METRICS = 8
  MAX_FILTER_LENGTH = 80
  MAX_ATTRIBUTE_KEYS = 12
  MAX_ATTRIBUTE_VALUES = 25
  MAX_ATTRIBUTE_FILTERS = 6
  METRIC_CATALOG_SAMPLE_LIMIT = 1_000
  ATTRIBUTE_CATALOG_SAMPLE_LIMIT = 500
  ATTRIBUTE_KEY_PATTERN = /\A[a-z][a-z0-9_.:-]{0,63}\z/
  NUMERIC_SQL_PATTERN = "^-?[0-9]+(\\.[0-9]+)?$"
  NUMERIC_CONTEXT_KEYS = %w[
    duration_ms
    durationMs
    value
  ].freeze

  RESERVED_ATTRIBUTE_KEYS = %w[
    backtrace
    breadcrumbs
    check_in_slug
    check_in_status
    duration_ms
    durationMs
    environment
    exception
    expected_interval_seconds
    params
    query
    release
    request
    request_id
    requestId
    response
    session_id
    sessionId
    sql
    stacktrace
    trace_id
    traceId
    transaction_name
    transactionName
    user_id
    userId
    value
  ].freeze

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

  METRIC_CATEGORY_LABELS = {
    "health" => "Health",
    "activity" => "Activity",
    "performance" => "Performance",
    "monitors" => "Monitors",
    "metrics" => "Custom metrics"
  }.freeze

  BASE_METRICS = {
    "events.total" => {
      key: "events.total",
      label: "Total events",
      description: "Every activity, error, metric, transaction, and check-in event.",
      unit: "count",
      kind: "count",
      source: "Activity",
      category: "activity",
      category_label: METRIC_CATEGORY_LABELS.fetch("activity")
    },
    "errors.count" => {
      key: "errors.count",
      label: "Errors",
      description: "Error events captured by the project.",
      unit: "count",
      kind: "count",
      source: "Inbox",
      category: "health",
      category_label: METRIC_CATEGORY_LABELS.fetch("health")
    },
    "activity.count" => {
      key: "activity.count",
      label: "Activity events",
      description: "Non-error events flowing into Activity.",
      unit: "count",
      kind: "count",
      source: "Activity",
      category: "activity",
      category_label: METRIC_CATEGORY_LABELS.fetch("activity")
    },
    "logs.count" => {
      key: "logs.count",
      label: "Logs",
      description: "Log events captured by the project.",
      unit: "count",
      kind: "count",
      source: "Activity",
      category: "activity",
      category_label: METRIC_CATEGORY_LABELS.fetch("activity")
    },
    "check_ins.count" => {
      key: "check_ins.count",
      label: "Check-ins",
      description: "Monitor check-in events captured by the project.",
      unit: "count",
      kind: "count",
      source: "Activity",
      category: "monitors",
      category_label: METRIC_CATEGORY_LABELS.fetch("monitors")
    },
    "transactions.count" => {
      key: "transactions.count",
      label: "Transactions",
      description: "Transaction events from Performance.",
      unit: "count",
      kind: "count",
      source: "Performance",
      category: "performance",
      category_label: METRIC_CATEGORY_LABELS.fetch("performance")
    },
    "transactions.avg" => {
      key: "transactions.avg",
      label: "Avg transaction duration",
      description: "Average transaction duration from Performance.",
      unit: "ms",
      kind: "duration",
      source: "Performance",
      category: "performance",
      category_label: METRIC_CATEGORY_LABELS.fetch("performance")
    },
    "transactions.p95" => {
      key: "transactions.p95",
      label: "P95 transaction duration",
      description: "95th percentile transaction duration from Performance.",
      unit: "ms",
      kind: "duration",
      source: "Performance",
      category: "performance",
      category_label: METRIC_CATEGORY_LABELS.fetch("performance")
    },
    "db.query.count" => {
      key: "db.query.count",
      label: "DB queries",
      description: "Database query metric events.",
      unit: "count",
      kind: "count",
      source: "Performance",
      category: "performance",
      category_label: METRIC_CATEGORY_LABELS.fetch("performance")
    },
    "db.query.avg" => {
      key: "db.query.avg",
      label: "Avg DB query duration",
      description: "Average database query duration.",
      unit: "ms",
      kind: "duration",
      source: "Performance",
      category: "performance",
      category_label: METRIC_CATEGORY_LABELS.fetch("performance")
    },
    "db.query.p95" => {
      key: "db.query.p95",
      label: "P95 DB query duration",
      description: "95th percentile database query duration.",
      unit: "ms",
      kind: "duration",
      source: "Performance",
      category: "performance",
      category_label: METRIC_CATEGORY_LABELS.fetch("performance")
    }
  }.freeze

  DEFAULT_METRIC_KEYS = %w[
    events.total
    errors.count
    transactions.p95
    db.query.avg
  ].freeze

  EVENT_TYPE_COUNT_COLUMNS = {
    "error" => "errors_count",
    "log" => "logs_count",
    "metric" => "metrics_count",
    "transaction" => "transactions_count",
    "check_in" => "check_ins_count"
  }.freeze

  STANDARD_METRIC_COLUMNS = {
    "events.total" => "events_total",
    "errors.count" => "errors_count",
    "activity.count" => "activity_count",
    "logs.count" => "logs_count",
    "check_ins.count" => "check_ins_count",
    "transactions.count" => "transactions_count",
    "transactions.avg" => "transactions_avg",
    "transactions.p95" => "transactions_p95",
    "db.query.count" => "db_query_count",
    "db.query.avg" => "db_query_avg",
    "db.query.p95" => "db_query_p95"
  }.freeze

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

    def shell_payload(project, endpoint:, window: DEFAULT_WINDOW, refresh_seconds: 30, storage_key: nil)
      {
        project_uuid: project.uuid,
        endpoint: endpoint,
        default_window: normalize_window(window),
        refresh_seconds: refresh_seconds,
        storage_key: storage_key,
        windows: window_options,
        event_types: event_type_catalog,
        default_metrics: default_metric_keys,
        metric_catalog: [],
        environments: [],
        releases: [],
        attributes: []
      }.compact
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
        releases: releases_for(project, window: window),
        attributes: attribute_catalog_for(project, window: window)
      }
    end

    def dashboard_for(project, window:, metrics:, environment:, release:, attribute_filters: nil, catalog: nil, filter_options: nil)
      window_key = normalize_window(window)
      since = since_for(window_key)
      catalog ||= catalog_for(project, window: window_key)
      filter_options ||= self.filter_options(project, window: window_key)
      attribute_catalog = filter_options.fetch(:attributes)
      selected_metrics = normalize_metric_keys(metrics, catalog)
      selected_attribute_filters = normalize_attribute_filters(attribute_filters, attribute_catalog)
      attribute_filter_values = selected_attribute_filters.transform_values { |filter| filter.fetch(:value) }
      filters = {
        environment: normalize_filter(environment),
        release: normalize_filter(release),
        attributes: attribute_filter_values
      }
      scope = events_scope(
        project,
        since: since,
        environment: filters[:environment],
        release: filters[:release],
        attribute_filters: selected_attribute_filters
      )
      bucket = WINDOW_OPTIONS.fetch(window_key).fetch(:bucket)
      buckets = buckets_for(since, bucket)
      summary = summary_for(scope)
      standard_bucket_rows = standard_bucket_rows(scope, bucket)

      {
        generated_at: Time.current.utc.iso8601,
        window: window_key,
        bucket: bucket,
        buckets: buckets.map { |bucket_time| bucket_time.utc.iso8601 },
        filters: filters.compact_blank,
        attribute_filters: selected_attribute_filters.map do |key, filter|
          { key: key, label: attribute_label(key), value: filter.fetch(:value), type: filter.fetch(:type) }
        end,
        summary: summary,
        event_type_catalog: event_type_catalog,
        event_timeline: event_timeline(standard_bucket_rows, buckets, bucket),
        event_types: event_type_breakdown(summary),
        metric_catalog: metric_catalog_with_availability(catalog, scope, summary, standard_bucket_rows),
        selected_metrics: selected_metrics,
        metric_series: metric_series(scope, selected_metrics, catalog, buckets, bucket, standard_bucket_rows),
        environments: filter_options.fetch(:environments),
        releases: filter_options.fetch(:releases),
        attributes: attribute_catalog,
        recent_events: recent_events(scope)
      }
    end

    def environments_for(project, window: DEFAULT_WINDOW)
      since = since_for(normalize_window(window))
      counts = project.ingest_events
                      .where("occurred_at >= ?", since)
                      .group(environment_node)
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

    def attribute_catalog_for(project, window: DEFAULT_WINDOW)
      since = since_for(normalize_window(window))
      sql = <<~SQL.squish
        SELECT
          attrs.key AS attribute_key,
          attrs.value #>> '{}' AS attribute_value,
          jsonb_typeof(attrs.value) AS attribute_type,
          COUNT(*) AS count
        FROM (
          SELECT context
          FROM ingest_events
          WHERE project_id = #{ApplicationRecord.connection.quote(project.id)}
            AND occurred_at >= #{ApplicationRecord.connection.quote(since)}
          ORDER BY occurred_at DESC
          LIMIT #{ATTRIBUTE_CATALOG_SAMPLE_LIMIT}
        ) sampled_events
        CROSS JOIN LATERAL jsonb_each(sampled_events.context) AS attrs(key, value)
        WHERE attrs.value #>> '{}' <> ''
          AND jsonb_typeof(attrs.value) IN ('string', 'number', 'boolean')
        GROUP BY attrs.key, attrs.value, jsonb_typeof(attrs.value)
        ORDER BY COUNT(*) DESC
        LIMIT #{(MAX_ATTRIBUTE_KEYS * MAX_ATTRIBUTE_VALUES * 3).to_i}
      SQL

      rows = ApplicationRecord.connection.exec_query(sql)
      grouped = rows.each_with_object({}) do |row, attributes|
        key = row.fetch("attribute_key").to_s
        next unless visible_attribute_key?(key)

        value = normalize_filter(row.fetch("attribute_value"))
        next if value.blank?

        attributes[key] ||= { count: 0, values: [] }
        attributes[key][:count] += row.fetch("count").to_i
        attributes[key][:values] << { name: value, type: row.fetch("attribute_type"), count: row.fetch("count").to_i }
      end

      grouped.sort_by { |key, payload| [ -payload[:count], key ] }
             .first(MAX_ATTRIBUTE_KEYS)
             .map do |key, payload|
        {
          key: key,
          label: attribute_label(key),
          count: payload.fetch(:count),
          values: payload.fetch(:values)
                         .sort_by { |value| [ -value.fetch(:count), value.fetch(:name) ] }
                         .first(MAX_ATTRIBUTE_VALUES)
        }
      end
    end

    private

    def custom_metric_catalog(project, since)
      sampled_metrics = sampled_metric_events(project, since)
      counts = sampled_metrics.group(:message)
                              .order(Arel.sql("COUNT(*) DESC"))
                              .limit(MAX_CUSTOM_METRICS)
                              .count
      numeric_counts = numeric_custom_metric_counts(sampled_metrics)

      counts.flat_map do |message, count|
        name = message.to_s.strip
        next [] if name.blank?

        count_metric = {
          key: custom_metric_key(name),
          label: name.truncate(64),
          description: "Metric event count for #{name.truncate(80)}.",
          unit: "count",
          kind: "count",
          source: "Metrics",
          category: "metrics",
          category_label: METRIC_CATEGORY_LABELS.fetch("metrics"),
          events: count
        }

        next [ count_metric ] unless numeric_counts.key?(name)

        [
          count_metric,
          {
            key: custom_metric_value_key(name),
            label: "Avg #{name.truncate(58)}",
            description: "Average numeric context.value for #{name.truncate(80)}.",
            unit: "value",
            kind: "number",
            source: "Metrics",
            category: "metrics",
            category_label: METRIC_CATEGORY_LABELS.fetch("metrics"),
            events: numeric_counts.fetch(name)
          }
        ]
      end
    end

    def sampled_metric_events(project, since)
      recent_metrics = project.ingest_events
                              .where(event_type: IngestEvent.event_types.fetch("metric"))
                              .where.not(message: "db.query")
                              .where("occurred_at >= ?", since)
                              .select(:message, :context, :occurred_at)
                              .order(occurred_at: :desc)
                              .limit(METRIC_CATALOG_SAMPLE_LIMIT)

      IngestEvent.from(recent_metrics, :ingest_events)
    end

    def numeric_custom_metric_counts(sampled_metrics)
      value_node = numeric_context_value_node("value")

      sampled_metrics.where(value_node.not_eq(nil))
                     .group(:message)
                     .count
                     .transform_keys { |message| message.to_s.strip }
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

    def normalize_attribute_filters(filters, attribute_catalog)
      catalog_by_key = attribute_catalog.index_by { |attribute| attribute.fetch(:key) }
      raw_filters =
        if filters.respond_to?(:to_unsafe_h)
          filters.to_unsafe_h
        elsif filters.respond_to?(:to_h)
          filters.to_h
        else
          {}
        end

      raw_filters.each_with_object({}) do |(key, value), normalized|
        break normalized if normalized.size >= MAX_ATTRIBUTE_FILTERS

        key = key.to_s
        attribute = catalog_by_key[key]
        next if attribute.blank?

        value = normalize_filter(value)
        next if value.blank?

        catalog_value = attribute.fetch(:values).find { |option| option.fetch(:name) == value }
        next if catalog_value.blank?

        normalized[key] = { value: value, type: catalog_value.fetch(:type) }
      end
    end

    def since_for(window)
      WINDOW_OPTIONS.fetch(window).fetch(:duration).ago
    end

    def events_scope(project, since:, environment:, release:, attribute_filters:)
      scope = project.ingest_events.where("occurred_at >= ?", since)
      scope = scope.where(environment_node.eq(environment)) if environment.present?
      scope = scope.where("context->>'release' = ?", release) if release.present?
      attribute_filters.each do |key, filter|
        scope = apply_attribute_filter(scope, key, filter)
      end
      scope
    end

    def apply_attribute_filter(scope, key, filter)
      value = typed_attribute_value(filter.fetch(:value), filter.fetch(:type))

      scope.where("context @> ?::jsonb", { key => value }.to_json)
    end

    def typed_attribute_value(value, type)
      case type
      when "number"
        numeric_attribute_value(value)
      when "boolean"
        value.to_s == "true"
      else
        value.to_s
      end
    end

    def numeric_attribute_value(value)
      value = value.to_s
      return value.to_i if value.match?(/\A-?\d+\z/)

      Float(value)
    rescue ArgumentError, TypeError
      value
    end

    def summary_for(scope)
      row = aggregate_row_for(
        scope,
        columns: [ :event_type, :occurred_at ],
        select_sql: <<~SQL.squish,
          COUNT(*) AS events,
          COUNT(*) FILTER (WHERE event_type = ?) AS errors,
          COUNT(*) FILTER (WHERE event_type = ?) AS logs,
          COUNT(*) FILTER (WHERE event_type = ?) AS metrics,
          COUNT(*) FILTER (WHERE event_type = ?) AS transactions,
          COUNT(*) FILTER (WHERE event_type = ?) AS check_ins,
          MAX(occurred_at) AS latest_event_at
        SQL
        binds: [
          event_type_value("error"),
          event_type_value("log"),
          event_type_value("metric"),
          event_type_value("transaction"),
          event_type_value("check_in")
        ]
      )
      total_events = row.fetch("events").to_i
      errors = row.fetch("errors").to_i

      {
        events: total_events,
        errors: errors,
        activity: total_events - errors,
        logs: row.fetch("logs").to_i,
        metrics: row.fetch("metrics").to_i,
        transactions: row.fetch("transactions").to_i,
        check_ins: row.fetch("check_ins").to_i,
        latest_event_at: row.fetch("latest_event_at")&.utc&.iso8601
      }
    end

    def event_type_breakdown(summary)
      EVENT_TYPE_LABELS.map do |key, label|
        count = key == "error" ? summary.fetch(:errors, 0) : summary.fetch(key.pluralize.to_sym, 0)
        { key: key, label: label, count: count, color: EVENT_TYPE_COLORS.fetch(key) }
      end
    end

    def event_timeline(standard_bucket_rows, buckets, bucket)
      rows = standard_bucket_rows_by_timestamp(standard_bucket_rows, bucket)
      buckets.map do |bucket_time|
        timestamp = bucket_time.utc.iso8601
        bucket_row = rows[timestamp]
        row = { timestamp: timestamp }
        EVENT_TYPE_LABELS.keys.each do |event_type|
          row[event_type] = bucket_row.to_h.fetch(EVENT_TYPE_COUNT_COLUMNS.fetch(event_type), 0).to_i
        end
        row
      end
    end

    def standard_bucket_rows(scope, bucket)
      merge_standard_bucket_rows(
        bucket,
        event_bucket_rows(scope, bucket),
        transaction_duration_bucket_rows(scope, bucket),
        db_query_bucket_rows(scope, bucket)
      )
    end

    def event_bucket_rows(scope, bucket)
      bucket_sql = bucket_sql_for(bucket)
      sql = sanitized_sql_query(
        <<~SQL.squish,
          SELECT
            %{bucket_sql} AS bucket_time,
            COUNT(*) AS events_total,
            COUNT(*) FILTER (WHERE event_type = ?) AS errors_count,
            COUNT(*) FILTER (WHERE event_type <> ?) AS activity_count,
            COUNT(*) FILTER (WHERE event_type = ?) AS logs_count,
            COUNT(*) FILTER (WHERE event_type = ?) AS metrics_count,
            COUNT(*) FILTER (WHERE event_type = ?) AS check_ins_count,
            COUNT(*) FILTER (WHERE event_type = ?) AS transactions_count
          FROM (%{events_scope_sql}) scoped_events
          GROUP BY bucket_time
        SQL
        binds: [
          event_type_value("error"),
          event_type_value("error"),
          event_type_value("log"),
          event_type_value("metric"),
          event_type_value("check_in"),
          event_type_value("transaction")
        ],
        fragments: {
          bucket_sql: bucket_sql,
          events_scope_sql: events_scope_sql(scope, :event_type, :occurred_at)
        }
      )

      connection.exec_query(sql).to_a
    end

    def transaction_duration_bucket_rows(scope, bucket)
      bucket_sql = bucket_sql_for(bucket)
      duration_scope = scope.where(event_type: event_type_value("transaction"))
      sql = sanitized_sql_query(
        <<~SQL.squish,
          SELECT
            %{bucket_sql} AS bucket_time,
            COUNT(*) FILTER (WHERE duration_value IS NOT NULL) AS transactions_duration_count,
            AVG(duration_value) FILTER (WHERE duration_value IS NOT NULL) AS transactions_avg,
            percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_value) FILTER (WHERE duration_value IS NOT NULL) AS transactions_p95
          FROM (
            SELECT
              occurred_at,
              %{duration_value_sql} AS duration_value
            FROM (%{events_scope_sql}) scoped_events
          ) transaction_events
          GROUP BY bucket_time
        SQL
        fragments: {
          bucket_sql: bucket_sql,
          duration_value_sql: numeric_duration_value_sql,
          events_scope_sql: events_scope_sql(duration_scope, :occurred_at, :context)
        }
      )

      connection.exec_query(sql).to_a
    end

    def db_query_bucket_rows(scope, bucket)
      bucket_sql = bucket_sql_for(bucket)
      duration_scope = db_query_scope(scope)
      sql = sanitized_sql_query(
        <<~SQL.squish,
          SELECT
            %{bucket_sql} AS bucket_time,
            COUNT(*) AS db_query_count,
            COUNT(*) FILTER (WHERE duration_value IS NOT NULL) AS db_query_duration_count,
            AVG(duration_value) FILTER (WHERE duration_value IS NOT NULL) AS db_query_avg,
            percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_value) FILTER (WHERE duration_value IS NOT NULL) AS db_query_p95
          FROM (
            SELECT
              occurred_at,
              %{duration_value_sql} AS duration_value
            FROM (%{events_scope_sql}) scoped_events
          ) db_query_events
          GROUP BY bucket_time
        SQL
        fragments: {
          bucket_sql: bucket_sql,
          duration_value_sql: numeric_duration_value_sql,
          events_scope_sql: events_scope_sql(duration_scope, :occurred_at, :context)
        }
      )

      connection.exec_query(sql).to_a
    end

    def merge_standard_bucket_rows(bucket, *row_sets)
      row_sets.each_with_object({}) do |rows, merged_rows|
        rows.each do |row|
          timestamp = bucket_timestamp(row.fetch("bucket_time"), bucket)
          merged_rows[timestamp] ||= { "bucket_time" => row.fetch("bucket_time") }
          merged_rows[timestamp].merge!(row)
        end
      end.values
    end

    def standard_bucket_rows_by_timestamp(standard_bucket_rows, bucket)
      standard_bucket_rows.index_by { |row| bucket_timestamp(row.fetch("bucket_time"), bucket) }
    end

    def bucket_sql_for(bucket)
      "date_trunc(#{connection.quote(valid_bucket_name(bucket))}, occurred_at)"
    end

    def duration_value_sql
      raw_value = duration_context_value_sql
      duration_event_condition = sanitize_sql_array([
        <<~SQL.squish,
          (
            event_type = ?
            OR (event_type = ? AND message = ?)
          )
        SQL
        event_type_value("transaction"),
        event_type_value("metric"),
        db_query_message
      ])

      "CASE WHEN #{duration_event_condition} AND #{raw_value} ~ #{connection.quote(NUMERIC_SQL_PATTERN)} THEN (#{raw_value})::double precision END"
    end

    def numeric_duration_value_sql
      raw_value = duration_context_value_sql

      "CASE WHEN #{raw_value} ~ #{connection.quote(NUMERIC_SQL_PATTERN)} THEN (#{raw_value})::double precision END"
    end

    def duration_context_value_sql
      "COALESCE(context->>'duration_ms', context->>'durationMs')"
    end

    def aggregate_row_for(scope, columns:, select_sql:, binds: [])
      sql = sanitized_sql_query(
        <<~SQL.squish,
          SELECT #{select_sql}
          FROM (%{events_scope_sql}) scoped_events
        SQL
        binds: binds,
        fragments: { events_scope_sql: events_scope_sql(scope, *columns) }
      )

      connection.exec_query(sql).first || {}
    end

    def sanitized_sql_query(template, binds: [], fragments: {})
      sql = binds.present? ? sanitize_sql_array([ template, *binds ]) : template
      format(sql, **fragments.symbolize_keys)
    end

    def sanitize_sql_array(value)
      ApplicationRecord.sanitize_sql_array(value)
    end

    def event_type_value(event_type)
      IngestEvent.event_types.fetch(event_type)
    end

    def db_query_message
      "db.query"
    end

    def events_scope_sql(scope, *columns)
      scope.except(:select, :order, :limit, :offset, :group).select(*columns).to_sql
    end

    def connection
      ApplicationRecord.connection
    end

    def metric_series(scope, metric_keys, catalog, buckets, bucket, standard_bucket_rows)
      definitions = catalog.index_by { |metric| metric.fetch(:key) }
      standard_rows = standard_bucket_rows_by_timestamp(standard_bucket_rows, bucket)

      metric_keys.filter_map do |metric_key|
        definition = definitions[metric_key]
        next if definition.blank?

        {
          key: metric_key,
          label: definition.fetch(:label),
          unit: definition.fetch(:unit),
          kind: definition.fetch(:kind),
          source: definition.fetch(:source),
          data: standard_metric_key?(metric_key) ? standard_metric_data(metric_key, standard_rows, buckets) : metric_data(scope, metric_key, buckets, bucket)
        }
      end
    end

    def standard_metric_key?(metric_key)
      STANDARD_METRIC_COLUMNS.key?(metric_key)
    end

    def standard_metric_data(metric_key, standard_rows, buckets)
      column = STANDARD_METRIC_COLUMNS.fetch(metric_key)

      buckets.map do |bucket_time|
        timestamp = bucket_time.utc.iso8601
        value = standard_rows.fetch(timestamp, {}).fetch(column, 0)
        { timestamp: timestamp, value: value.to_f.round(2) }
      end
    end

    def metric_catalog_with_availability(catalog, scope, summary, standard_bucket_rows)
      availability = metric_availability_counts(catalog, scope, summary, standard_bucket_rows)

      catalog.map do |metric|
        matching_events = availability.fetch(metric.fetch(:key), 0)

        metric.merge(available: matching_events.positive?, available_events: matching_events)
      end
    end

    def metric_availability_counts(catalog, scope, summary, standard_bucket_rows)
      base_counts = {
        "events.total" => summary.fetch(:events, 0),
        "errors.count" => summary.fetch(:errors, 0),
        "activity.count" => summary.fetch(:activity, 0),
        "logs.count" => summary.fetch(:logs, 0),
        "check_ins.count" => summary.fetch(:check_ins, 0),
        "transactions.count" => summary.fetch(:transactions, 0)
      }

      base_counts
        .merge(standard_metric_availability_counts(standard_bucket_rows))
        .merge(custom_metric_availability_counts(catalog, scope))
    end

    def standard_metric_availability_counts(standard_bucket_rows)
      transaction_duration_count = sum_standard_bucket_column(standard_bucket_rows, "transactions_duration_count")
      db_query_count = sum_standard_bucket_column(standard_bucket_rows, "db_query_count")
      db_query_duration_count = sum_standard_bucket_column(standard_bucket_rows, "db_query_duration_count")

      {
        "transactions.avg" => transaction_duration_count,
        "transactions.p95" => transaction_duration_count,
        "db.query.count" => db_query_count,
        "db.query.avg" => db_query_duration_count,
        "db.query.p95" => db_query_duration_count
      }
    end

    def sum_standard_bucket_column(standard_bucket_rows, column)
      standard_bucket_rows.sum { |row| row.fetch(column, 0).to_i }
    end

    def custom_metric_availability_counts(catalog, scope)
      names = custom_metric_catalog_names(catalog)
      return {} if names.blank?

      custom_scope = scope.where(event_type: IngestEvent.event_types.fetch("metric"), message: names)
      counts = custom_scope.group(:message).count.transform_keys(&:to_s)
      numeric_counts = custom_scope.where(numeric_context_value_node("value").not_eq(nil))
                                   .group(:message)
                                   .count
                                   .transform_keys(&:to_s)

      names.each_with_object({}) do |name, availability|
        availability[custom_metric_key(name)] = counts.fetch(name, 0)
        availability[custom_metric_value_key(name)] = numeric_counts.fetch(name, 0)
      end
    end

    def duration_event_count(scope)
      scope.where(duration_value_node.not_eq(nil)).count
    end

    def custom_metric_catalog_names(catalog)
      catalog.filter_map do |metric|
        key = metric.fetch(:key)
        if key.start_with?("metric_value:")
          custom_metric_value_name(key)
        elsif key.start_with?("metric:")
          custom_metric_name(key)
        end
      end.uniq
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
        if metric_key.start_with?("metric_value:")
          numeric_value_data(
            scope.where(event_type: IngestEvent.event_types.fetch("metric"), message: custom_metric_value_name(metric_key)),
            buckets,
            bucket,
            context_key: "value"
          )
        elsif metric_key.start_with?("metric:")
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
      counts = scope.group(bucket_node(bucket)).count
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

    def numeric_value_data(scope, buckets, bucket, context_key:)
      values = numeric_values(scope, bucket, context_key: context_key)

      buckets.map do |bucket_time|
        value = values.fetch(bucket_time.utc.iso8601, 0)
        { timestamp: bucket_time.utc.iso8601, value: value.to_f.round(2) }
      end
    end

    def duration_values(scope, bucket, aggregate)
      node = bucket_node(bucket)
      duration_node = duration_value_node
      aggregate_node = aggregate_node_for(aggregate, duration_node)

      scope.where(duration_node.not_eq(nil)).group(node).pluck(node, aggregate_node).each_with_object({}) do |(bucket_time, value), values|
        values[bucket_timestamp(bucket_time, bucket)] = value.to_f
      end
    end

    def numeric_values(scope, bucket, context_key:)
      node = bucket_node(bucket)
      value_node = numeric_context_value_node(context_key)
      aggregate_node = Arel::Nodes::NamedFunction.new("AVG", [ value_node ])

      scope.where(value_node.not_eq(nil)).group(node).pluck(node, aggregate_node).each_with_object({}) do |(bucket_time, value), values|
        values[bucket_timestamp(bucket_time, bucket)] = value.to_f
      end
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

    def bucket_node(bucket)
      Arel::Nodes::NamedFunction.new(
        "date_trunc",
        [ Arel::Nodes.build_quoted(valid_bucket_name(bucket)), ingest_events_table[:occurred_at] ]
      )
    end

    def valid_bucket_name(bucket)
      bucket = bucket.to_s
      return bucket if WINDOW_OPTIONS.values.any? { |option| option.fetch(:bucket) == bucket }

      raise ArgumentError, "Unsupported insights bucket: #{bucket.inspect}"
    end

    def environment_node
      Arel::Nodes::NamedFunction.new(
        "COALESCE",
        [
          Arel::Nodes::NamedFunction.new("NULLIF", [ json_text_node("environment"), Arel::Nodes.build_quoted("") ]),
          Arel::Nodes.build_quoted("unknown")
        ]
      )
    end

    def duration_value_node
      raw_duration = Arel::Nodes::NamedFunction.new(
        "COALESCE",
        [ json_text_node("duration_ms"), json_text_node("durationMs") ]
      )

      numeric_case_node(raw_duration)
    end

    def numeric_context_value_node(context_key)
      numeric_case_node(json_text_node(valid_numeric_context_key(context_key)))
    end

    def json_text_node(context_key)
      Arel::Nodes::InfixOperation.new(
        "->>",
        ingest_events_table[:context],
        Arel::Nodes.build_quoted(context_key)
      )
    end

    def numeric_case_node(raw_value)
      Arel::Nodes::Case.new
                       .when(Arel::Nodes::Regexp.new(raw_value, Arel::Nodes.build_quoted(NUMERIC_SQL_PATTERN)))
                       .then(double_precision_cast_node(raw_value))
                       .else(nil)
    end

    def double_precision_cast_node(node)
      Arel::Nodes::NamedFunction.new("CAST", [ node.as(Arel.sql("double precision")) ])
    end

    def aggregate_node_for(aggregate, value_node)
      return Arel::Nodes::NamedFunction.new("AVG", [ value_node ]) unless aggregate == :p95

      percentile_node = Arel::Nodes::NamedFunction.new("percentile_cont", [ Arel::Nodes.build_quoted(0.95) ])
      ordering_node = Arel::Nodes::Window.new.order(value_node)

      Arel::Nodes::InfixOperation.new("WITHIN GROUP", percentile_node, ordering_node)
    end

    def valid_numeric_context_key(context_key)
      context_key = context_key.to_s
      return context_key if NUMERIC_CONTEXT_KEYS.include?(context_key)

      raise ArgumentError, "Unsupported numeric context key: #{context_key.inspect}"
    end

    def ingest_events_table
      IngestEvent.arel_table
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
          duration_ms: duration_value(context),
          attributes: event_attributes(context)
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
      counts.sort_by { |name, count| [ -count, name.to_s ] }
            .first(20)
            .map { |name, count| { name: name.presence || "unknown", count: count } }
    end

    def event_attributes(context)
      attributes = []

      context.each do |key, value|
        next unless visible_attribute_key?(key)
        next unless scalar_attribute_value?(value)

        normalized_value = normalize_filter(value)
        next if normalized_value.blank?

        attributes << { key: key, label: attribute_label(key), value: normalized_value }
        break if attributes.size >= 5
      end

      attributes
    end

    def visible_attribute_key?(key)
      key = key.to_s
      key.match?(ATTRIBUTE_KEY_PATTERN) &&
        key == canonical_attribute_key(key) &&
        !RESERVED_ATTRIBUTE_KEYS.include?(key)
    end

    def canonical_attribute_key(key)
      key.to_s.underscore.downcase
    end

    def scalar_attribute_value?(value)
      value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
    end

    def attribute_label(key)
      key.to_s.tr("_.:-", "    ").squish.titleize
    end

    def custom_metric_key(name)
      "metric:#{name}"
    end

    def custom_metric_name(metric_key)
      metric_key.delete_prefix("metric:")
    end

    def custom_metric_value_key(name)
      "metric_value:#{name}"
    end

    def custom_metric_value_name(metric_key)
      metric_key.delete_prefix("metric_value:")
    end
  end
end
