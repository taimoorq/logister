# frozen_string_literal: true

class ProjectInsights
  DEFAULT_WINDOW = "24h"
  MAX_CUSTOM_METRICS = 12
  MAX_SELECTED_METRICS = 8
  MAX_FILTER_LENGTH = 80
  MAX_ATTRIBUTE_KEYS = 12
  MAX_ATTRIBUTE_VALUES = 25
  MAX_ATTRIBUTE_FILTERS = 6
  METRIC_CATALOG_SAMPLE_LIMIT = 5_000
  ATTRIBUTE_CATALOG_SAMPLE_LIMIT = 2_000
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
        releases: releases_for(project, window: window),
        attributes: attribute_catalog_for(project, window: window)
      }
    end

    def dashboard_for(project, window:, metrics:, environment:, release:, attribute_filters: nil)
      window_key = normalize_window(window)
      since = since_for(window_key)
      catalog = catalog_for(project, window: window_key)
      attribute_catalog = attribute_catalog_for(project, window: window_key)
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

      {
        generated_at: Time.current.utc.iso8601,
        window: window_key,
        bucket: bucket,
        buckets: buckets.map { |bucket_time| bucket_time.utc.iso8601 },
        filters: filters.compact_blank,
        attribute_filters: selected_attribute_filters.map do |key, filter|
          { key: key, label: attribute_label(key), value: filter.fetch(:value), type: filter.fetch(:type) }
        end,
        summary: summary_for(scope),
        event_type_catalog: event_type_catalog,
        event_timeline: event_timeline(scope, buckets, bucket),
        event_types: event_type_breakdown(scope),
        metric_catalog: catalog,
        selected_metrics: selected_metrics,
        metric_series: metric_series(scope, selected_metrics, catalog, buckets, bucket),
        environments: environments_for(project, window: window_key),
        releases: releases_for(project, window: window_key),
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
      node = bucket_node(bucket)
      counts = scope.group(node, :event_type).count
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
