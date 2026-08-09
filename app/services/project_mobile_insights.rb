# frozen_string_literal: true

class ProjectMobileInsights
  MAX_CUSTOM_METRICS = 8
  MAX_SELECTED_METRICS = 8
  NUMERIC_PATTERN = "^-?[0-9]+(\\.[0-9]+)?$"
  METRIC = lambda do |key, label, description, unit, kind, source, category, category_label|
    { key:, label:, description:, unit:, kind:, source:, category:, category_label: }.freeze
  end

  METRICS = {
    "events.total" => METRIC.call("events.total", "All receipts", "Every error and app-activity receipt accepted in this scope.", "count", "count", "Mobile telemetry", "activity", "Activity"),
    "errors.count" => METRIC.call("errors.count", "Stability receipts", "Error and platform-diagnostic receipts. This is not a crash-free rate.", "count", "count", "Stability", "health", "Stability"),
    "activity.count" => METRIC.call("activity.count", "App activity receipts", "Non-error metrics, logs, transactions, and check-ins received from the app.", "count", "count", "App activity", "activity", "Activity"),
    "logs.count" => METRIC.call("logs.count", "Logs", "App log receipts in this scope.", "count", "count", "App activity", "activity", "Activity"),
    "metrics.count" => METRIC.call("metrics.count", "Metrics", "App-supplied metric receipts in this scope.", "count", "count", "App health", "metrics", "App metrics"),
    "transactions.count" => METRIC.call("transactions.count", "Transactions", "Explicitly instrumented app transaction receipts.", "count", "count", "App health", "performance", "App performance"),
    "transactions.p95" => METRIC.call("transactions.p95", "P95 transaction duration", "95th percentile of app-supplied transaction durations with valid millisecond values.", "ms", "duration", "App health", "performance", "App performance"),
    "check_ins.count" => METRIC.call("check_ins.count", "Check-ins", "App check-in receipts. This is separate from platform diagnostics.", "count", "count", "App activity", "monitors", "Check-ins")
  }.freeze

  LENSES = [
    { key: "stability", label: "Stability", description: "Diagnostics + receipt quality", metrics: %w[errors.count events.total] },
    { key: "activity", label: "App activity", description: "Logs + app telemetry", metrics: %w[activity.count logs.count metrics.count check_ins.count] },
    { key: "performance", label: "App performance", description: "Instrumented app work", metrics: %w[transactions.count transactions.p95 metrics.count] },
    { key: "custom", label: "Custom", description: "App metric series", metrics: [] }
  ].freeze

  ATTRIBUTE_EXPRESSIONS = {
    "evidence_source" => "COALESCE(NULLIF(ingest_events.context #>> '{telemetry_evidence,source}', ''), NULLIF(ingest_events.context #>> '{diagnostic,source}', ''), 'sdk')",
    "time_precision" => "COALESCE(NULLIF(ingest_events.context #>> '{telemetry_evidence,time,precision}', ''), 'unknown')",
    "build_number" => "COALESCE(NULLIF(ingest_events.context #>> '{app,version_code}', ''), 'not_captured')",
    "distribution_channel" => "COALESCE(NULLIF(ingest_events.context #>> '{distribution,channel}', ''), NULLIF(ingest_events.context #>> '{distribution,track}', ''), 'not_captured')",
    "platform" => "COALESCE(NULLIF(ingest_events.context->>'apple_platform', ''), NULLIF(ingest_events.context->>'platform', ''), 'unknown')"
  }.freeze
  ATTRIBUTE_LABELS = {
    "evidence_source" => "Source",
    "time_precision" => "Evidence time",
    "build_number" => "Build",
    "distribution_channel" => "Distribution",
    "platform" => "Platform"
  }.freeze

  class << self
    def metric(key, label, description, unit, kind, source, category, category_label)
      METRIC.call(key, label, description, unit, kind, source, category, category_label)
    end

    def shell_payload(project, endpoint:, window: ProjectInsights::DEFAULT_WINDOW, refresh_seconds: 30, storage_key: nil)
      {
        project_uuid: project.uuid,
        endpoint:,
        experience: "mobile",
        default_window: ProjectInsights.normalize_window(window),
        default_lens: "stability",
        refresh_seconds:,
        storage_key:,
        windows: ProjectInsights.window_options,
        event_types: ProjectInsights.event_type_catalog,
        default_metrics: LENSES.first.fetch(:metrics),
        lenses: LENSES,
        lens_presets: LENSES.index_by { |lens| lens.fetch(:key) }.transform_values { |lens| { metrics: lens.fetch(:metrics) } },
        evidence_clock: "received_at",
        evidence_clock_label: "Receipt time",
        metric_catalog: [],
        environments: [],
        releases: [],
        attributes: []
      }.compact
    end

    def catalog_for(project, window: ProjectInsights::DEFAULT_WINDOW)
      since = since_for(window)
      METRICS.values.map(&:dup) + custom_metric_catalog(project, since)
    end

    def filter_options(project, window: ProjectInsights::DEFAULT_WINDOW)
      since = since_for(window)
      scope = project.ingest_events.where(created_at: since..)
      {
        environments: ranked_options(scope.group(environment_expression).count),
        releases: ranked_options(scope.where("COALESCE(context->>'release', '') <> ''").group(Arel.sql("context->>'release'")).count),
        attributes: attribute_catalog(scope)
      }
    end

    def dashboard_for(project, window:, metrics:, environment:, release:, attribute_filters: nil, catalog: nil, filter_options: nil)
      window_key = ProjectInsights.normalize_window(window)
      since = since_for(window_key)
      catalog ||= catalog_for(project, window: window_key)
      filter_options ||= self.filter_options(project, window: window_key)
      filters = normalized_attribute_filters(attribute_filters, filter_options.fetch(:attributes))
      scope = project.ingest_events.where(created_at: since..)
      scope = scope.where("#{environment_expression} = ?", environment) if environment.to_s.present?
      scope = scope.where("ingest_events.context->>'release' = ?", release) if release.to_s.present?
      filters.each { |key, value| scope = scope.where("#{ATTRIBUTE_EXPRESSIONS.fetch(key)} = ?", value) }

      bucket = ProjectInsights::WINDOW_OPTIONS.fetch(window_key).fetch(:bucket)
      buckets = buckets_for(since, bucket)
      selected = normalize_metrics(metrics, catalog)
      summary = summary_for(scope)
      event_counts = event_counts_by_bucket(scope, bucket)
      availability = metric_availability(scope, summary, catalog)

      {
        generated_at: Time.current.utc.iso8601,
        window: window_key,
        bucket:,
        buckets: buckets.map { |time| time.utc.iso8601 },
        evidence_clock: "received_at",
        evidence_clock_label: "Receipt time",
        completeness: completeness_for(scope, summary.fetch(:events)),
        filters: { environment: environment.to_s.presence, release: release.to_s.presence, attributes: filters }.compact_blank,
        attribute_filters: filters.map { |key, value| { key:, label: ATTRIBUTE_LABELS.fetch(key), value:, type: "string" } },
        summary:,
        event_type_catalog: ProjectInsights.event_type_catalog,
        event_timeline: event_timeline(event_counts, buckets),
        event_types: event_type_breakdown(summary),
        metric_catalog: catalog.map { |definition| definition.merge(available: availability.fetch(definition.fetch(:key), 0).positive?, available_events: availability.fetch(definition.fetch(:key), 0)) },
        selected_metrics: selected,
        metric_series: selected.filter_map { |key| metric_series_for(scope, key, catalog, buckets, bucket) },
        environments: filter_options.fetch(:environments),
        releases: filter_options.fetch(:releases),
        attributes: filter_options.fetch(:attributes),
        recent_events: recent_events(scope),
        analytics: { source: "postgres", clock: "received_at", profile: "mobile_v1" }
      }
    end

    private

    def since_for(window)
      Time.current - ProjectInsights::WINDOW_OPTIONS.fetch(ProjectInsights.normalize_window(window)).fetch(:duration)
    end

    def custom_metric_catalog(project, since)
      project.ingest_events.where(created_at: since.., event_type: :metric)
        .group(:message).order(Arel.sql("COUNT(*) DESC")).limit(MAX_CUSTOM_METRICS).count
        .map do |name, count|
          metric("metric:#{name}", name.to_s, "Receipt count for app metric #{name}.", "count", "count", "App metric", "metrics", "App metrics")
            .merge(events: count.to_i)
        end
    end

    def environment_expression
      "COALESCE(NULLIF(ingest_events.context->>'environment', ''), 'unknown')"
    end

    def ranked_options(counts)
      counts.sort_by { |name, count| [ -count, name.to_s ] }.first(20).map { |name, count| { name: name.to_s, count: count.to_i } }
    end

    def attribute_catalog(scope)
      ATTRIBUTE_EXPRESSIONS.map do |key, expression|
        counts = scope.group(Arel.sql(expression)).count
        {
          key:,
          label: ATTRIBUTE_LABELS.fetch(key),
          count: counts.values.sum,
          values: ranked_options(counts).map { |option| option.merge(type: "string") }
        }
      end
    end

    def normalized_attribute_filters(filters, catalog)
      allowed_values = catalog.index_by { |attribute| attribute.fetch(:key) }
      filters.to_h.stringify_keys.each_with_object({}) do |(key, value), result|
        next unless ATTRIBUTE_EXPRESSIONS.key?(key)
        next unless allowed_values.fetch(key).fetch(:values).any? { |option| option.fetch(:name) == value.to_s }

        result[key] = value.to_s
      end
    end

    def normalize_metrics(values, catalog)
      available = catalog.map { |metric| metric.fetch(:key) }
      selected = Array(values).map(&:to_s).select { |key| available.include?(key) }.uniq.first(MAX_SELECTED_METRICS)
      selected.presence || LENSES.first.fetch(:metrics)
    end

    def summary_for(scope)
      counts = scope.group(:event_type).count.transform_keys { |value| IngestEvent.event_types.key(value) || value.to_s }
      total = counts.values.sum
      errors = counts.fetch("error", 0)
      {
        events: total,
        errors:,
        activity: total - errors,
        logs: counts.fetch("log", 0),
        metrics: counts.fetch("metric", 0),
        transactions: counts.fetch("transaction", 0),
        check_ins: counts.fetch("check_in", 0),
        latest_event_at: scope.maximum(:created_at)&.utc&.iso8601
      }
    end

    def bucket_sql(bucket)
      "date_trunc(#{ApplicationRecord.connection.quote(bucket)}, ingest_events.created_at)"
    end

    def buckets_for(since, bucket)
      step = { "minute" => 1.minute, "hour" => 1.hour, "day" => 1.day }.fetch(bucket)
      current = floor_time(since, bucket)
      final = floor_time(Time.current, bucket)
      values = []
      while current <= final
        values << current
        current += step
      end
      values
    end

    def floor_time(time, bucket)
      case bucket
      when "minute" then time.change(sec: 0)
      when "hour" then time.change(min: 0, sec: 0)
      else time.beginning_of_day
      end
    end

    def event_counts_by_bucket(scope, bucket)
      scope.group(Arel.sql(bucket_sql(bucket)), :event_type).count.each_with_object({}) do |((time, type), count), result|
        timestamp = floor_time(time.to_time.utc, bucket).utc.iso8601
        result[timestamp] ||= Hash.new(0)
        result[timestamp][IngestEvent.event_types.key(type) || type.to_s] = count.to_i
      end
    end

    def event_timeline(counts, buckets)
      buckets.map do |time|
        timestamp = time.utc.iso8601
        values = counts.fetch(timestamp, {})
        { timestamp: }.merge(ProjectInsights::EVENT_TYPE_LABELS.keys.index_with { |key| values.fetch(key, 0) })
      end
    end

    def event_type_breakdown(summary)
      ProjectInsights.event_type_catalog.map do |definition|
        key = definition.fetch(:key)
        count_key = key == "error" ? :errors : key.pluralize.to_sym
        definition.merge(count: summary.fetch(count_key, 0))
      end
    end

    def metric_availability(scope, summary, catalog)
      transaction_durations = scope.where(event_type: :transaction).where("COALESCE(context->>'duration_ms', context->>'durationMs', '') ~ ?", NUMERIC_PATTERN).count
      values = {
        "events.total" => summary.fetch(:events),
        "errors.count" => summary.fetch(:errors),
        "activity.count" => summary.fetch(:activity),
        "logs.count" => summary.fetch(:logs),
        "metrics.count" => summary.fetch(:metrics),
        "transactions.count" => summary.fetch(:transactions),
        "transactions.p95" => transaction_durations,
        "check_ins.count" => summary.fetch(:check_ins)
      }
      catalog.each do |definition|
        key = definition.fetch(:key)
        values[key] = definition.fetch(:events, 0) if key.start_with?("metric:")
      end
      values
    end

    def metric_series_for(scope, key, catalog, buckets, bucket)
      definition = catalog.find { |metric| metric.fetch(:key) == key }
      return unless definition

      values = if key == "transactions.p95"
        transaction_p95(scope, bucket)
      else
        count_scope = metric_scope(scope, key)
        count_scope.group(Arel.sql(bucket_sql(bucket))).count.transform_keys { |time| floor_time(time.to_time.utc, bucket).utc.iso8601 }
      end
      {
        key:,
        label: definition.fetch(:label),
        description: definition.fetch(:description),
        unit: definition.fetch(:unit),
        kind: definition.fetch(:kind),
        source: definition.fetch(:source),
        data: buckets.map { |time| { timestamp: time.utc.iso8601, value: values.fetch(time.utc.iso8601, 0).to_f.round(2) } }
      }
    end

    def metric_scope(scope, key)
      case key
      when "events.total" then scope
      when "errors.count" then scope.where(event_type: :error)
      when "activity.count" then scope.where.not(event_type: :error)
      when "logs.count" then scope.where(event_type: :log)
      when "metrics.count" then scope.where(event_type: :metric)
      when "transactions.count" then scope.where(event_type: :transaction)
      when "check_ins.count" then scope.where(event_type: :check_in)
      else
        key.start_with?("metric:") ? scope.where(event_type: :metric, message: key.delete_prefix("metric:")) : scope.none
      end
    end

    def transaction_p95(scope, bucket)
      duration_sql = "(COALESCE(context->>'duration_ms', context->>'durationMs'))::double precision"
      scope.where(event_type: :transaction)
        .where("COALESCE(context->>'duration_ms', context->>'durationMs', '') ~ ?", NUMERIC_PATTERN)
        .group(Arel.sql(bucket_sql(bucket)))
        .pluck(Arel.sql(bucket_sql(bucket)), Arel.sql("percentile_cont(0.95) WITHIN GROUP (ORDER BY #{duration_sql})"))
        .to_h { |time, value| [ floor_time(time.to_time.utc, bucket).utc.iso8601, value.to_f ] }
    end

    def completeness_for(scope, total)
      source_count = scope.where("COALESCE(NULLIF(context #>> '{telemetry_evidence,source}', ''), NULLIF(context #>> '{diagnostic,source}', '')) IS NOT NULL").count
      precision_count = scope.where("COALESCE(NULLIF(context #>> '{telemetry_evidence,time,precision}', ''), '') <> ''").count
      {
        total_receipts: total,
        source_classified: source_count,
        time_precision_classified: precision_count,
        source_coverage: coverage_state(source_count, total),
        time_precision_coverage: coverage_state(precision_count, total)
      }
    end

    def coverage_state(count, total)
      return "not_applicable" if total.zero?
      return "not_collected" if count.zero?
      return "complete" if count == total

      "partial"
    end

    def recent_events(scope)
      scope.order(created_at: :desc, id: :desc).limit(12).map do |event|
        evidence = TelemetryEvidence.for(event)
        context = MobileTelemetryNormalizer.normalize(event.context)
        {
          uuid: event.uuid,
          event_type: event.event_type,
          label: ProjectInsights::EVENT_TYPE_LABELS.fetch(event.event_type, event.event_type.humanize),
          message: event.message,
          level: event.level,
          occurred_at: event.occurred_at.utc.iso8601,
          observed_at: event.created_at.utc.iso8601,
          time_precision: evidence.time_precision,
          evidence_source: evidence.source,
          environment: context["environment"].presence || "unknown",
          release: context["release"].presence,
          duration_ms: context["duration_ms"] || context["durationMs"],
          attributes: [
            { key: "evidence_source", label: "Source", value: evidence.source },
            { key: "time_precision", label: "Evidence time", value: evidence.time_precision }
          ]
        }
      end
    end
  end
end
