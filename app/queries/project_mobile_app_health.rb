# frozen_string_literal: true

class ProjectMobileAppHealth
  Diagnostic = Data.define(
    :kind,
    :count,
    :latest_received_at,
    :sources,
    :builds,
    :time_precisions,
    :evidence_role,
    :measurement,
    :latest_event
  )
  ActivityMetric = Data.define(:key, :label, :value, :unit, :coverage, :detail)
  Result = Data.define(:diagnostics, :activity_counts, :activity_metrics, :latest_activity_received_at, :window_started_at, :generated_at)

  attr_reader :project, :now, :window

  def initialize(project, now: Time.current, window: 30.days)
    raise ArgumentError, "Mobile app health is available only for Android and iOS projects" unless project.integration_android? || project.integration_ios?

    @project = project
    @now = now
    @window = window
  end

  def call
    started_at = now - window
    diagnostic_relation = diagnostic_scope(started_at)
    aggregates = diagnostic_relation
      .group(Arel.sql(diagnostic_kind_sql))
      .pluck(Arel.sql(diagnostic_kind_sql), Arel.sql("COUNT(*)"), Arel.sql("MAX(error_occurrences.created_at)"))
    facets = diagnostic_facets(diagnostic_relation)
    latest_events = latest_diagnostic_events(diagnostic_relation)
    diagnostics = aggregates.map do |kind, count, latest|
      kind = kind.to_s
      event = latest_events[kind]
      evidence = event && TelemetryEvidence.for(event)
      Diagnostic.new(
        kind:,
        count: count.to_i,
        latest_received_at: latest,
        sources: facets.dig(kind, :sources).to_h.keys.sort.freeze,
        builds: facets.dig(kind, :builds).to_h.keys.sort.freeze,
        time_precisions: facets.dig(kind, :time_precisions).to_h.keys.sort.freeze,
        evidence_role: evidence&.evidence_kind.to_s.presence&.humanize,
        measurement: measurement_for(event),
        latest_event: event
      ).freeze
    end
      .sort_by { |diagnostic| [ -diagnostic.count, diagnostic.kind ] }
      .freeze

    activity = project.ingest_events.where(created_at: started_at..).where.not(event_type: IngestEvent.event_types.fetch("error"))
    activity_counts = activity.group(:event_type).count.transform_keys { |value| IngestEvent.event_types.key(value) || value.to_s }.freeze
    Result.new(
      diagnostics:,
      activity_counts:,
      activity_metrics: activity_metrics(activity, activity_counts).freeze,
      latest_activity_received_at: activity.maximum(:created_at),
      window_started_at: started_at,
      generated_at: now
    ).freeze
  end

  private

  def diagnostic_scope(started_at)
    ErrorOccurrence.joins(:error_group)
      .where(error_groups: { project_id: project.id })
      .where(error_occurrences: { created_at: started_at.. })
  end

  def diagnostic_kind_sql
    if project.integration_ios?
      "COALESCE(NULLIF(error_occurrences.dimensions ->> 'diagnostic_kind', ''), NULLIF(error_occurrences.mechanism, ''), 'unknown_diagnostic')"
    else
      "COALESCE(NULLIF(error_occurrences.mechanism, ''), NULLIF(error_occurrences.dimensions ->> 'diagnostic_kind', ''), 'unknown_failure')"
    end
  end

  def diagnostic_facets(scope)
    result = Hash.new { |hash, kind| hash[kind] = { sources: {}, builds: {}, time_precisions: {} } }
    {
      sources: "COALESCE(NULLIF(error_occurrences.dimensions ->> 'diagnostic_source', ''), NULLIF(error_occurrences.dimensions ->> 'evidence_source', ''), 'not_captured')",
      builds: "COALESCE(NULLIF(error_occurrences.dimensions ->> 'build_number', ''), 'not_captured')",
      time_precisions: "COALESCE(NULLIF(error_occurrences.dimensions ->> 'time_precision', ''), 'unknown')"
    }.each do |facet, expression|
      scope.group(Arel.sql(diagnostic_kind_sql), Arel.sql(expression)).count.each do |(kind, value), count|
        result[kind.to_s][facet][value.to_s] = count.to_i
      end
    end
    result
  end

  def latest_diagnostic_events(scope)
    occurrences = scope
      .select(Arel.sql("DISTINCT ON (#{diagnostic_kind_sql}) error_occurrences.*"))
      .order(Arel.sql("#{diagnostic_kind_sql}, error_occurrences.created_at DESC, error_occurrences.id DESC"))
      .to_a
    events = IngestEvent.partition_reference_index(
      occurrences,
      id_key: :ingest_event_id,
      occurred_at_key: :ingest_event_occurred_at
    )
    occurrences.each_with_object({}) do |occurrence, result|
      kind = if project.integration_ios?
        occurrence.dimensions.to_h["diagnostic_kind"].presence || occurrence.mechanism.presence || "unknown_diagnostic"
      else
        occurrence.mechanism.presence || occurrence.dimensions.to_h["diagnostic_kind"].presence || "unknown_failure"
      end
      result[kind] = events[occurrence.ingest_event_id]
    end
  end

  def measurement_for(event)
    return unless event

    presenter = ProjectExperience.for(project).event_presenter(event)
    return presenter.measurement_summary if presenter.respond_to?(:measurement_summary) && presenter.measurement_summary.present?

    context = MobileTelemetryNormalizer.normalize(event.context)
    diagnostic = context["diagnostic"].is_a?(Hash) ? context["diagnostic"] : {}
    measurements = diagnostic["measurements"].is_a?(Hash) ? diagnostic["measurements"] : {}
    value = measurements["duration_ms"] || diagnostic["duration_ms"] || context["duration_ms"]
    "#{value} ms" if value.present?
  end

  def activity_metrics(scope, counts)
    transaction_scope = scope.where(event_type: IngestEvent.event_types.fetch("transaction"))
    duration_expression = "COALESCE(ingest_events.context->>'duration_ms', ingest_events.context->>'durationMs')"
    duration_scope = transaction_scope.where("#{duration_expression} ~ ?", "^-?[0-9]+(\\.[0-9]+)?$")
    duration_count = duration_scope.count
    p95 = duration_scope.pick(Arel.sql("percentile_cont(0.95) WITHIN GROUP (ORDER BY (#{duration_expression})::double precision)"))
    screen_count = scope.where("COALESCE(NULLIF(ingest_events.context #>> '{app,screen}', ''), NULLIF(ingest_events.context->>'screen_name', '')) IS NOT NULL").count
    metric_names = scope.where(event_type: IngestEvent.event_types.fetch("metric"))
      .group(:message).order(Arel.sql("COUNT(*) DESC")).limit(5).count.keys
    total = counts.values.sum
    transactions = counts.fetch("transaction", 0)

    [
      ActivityMetric.new(key: :transactions, label: "Instrumented transactions", value: transactions, unit: "receipts", coverage: coverage(duration_count, transactions), detail: "#{duration_count}/#{transactions} supplied a valid duration"),
      ActivityMetric.new(key: :transaction_p95, label: "P95 transaction duration", value: p95&.to_f&.round(1), unit: "ms", coverage: coverage(duration_count, transactions), detail: "App-supplied durations only"),
      ActivityMetric.new(key: :metrics, label: "App metric receipts", value: counts.fetch("metric", 0), unit: "receipts", coverage: :not_applicable, detail: metric_names.any? ? metric_names.join(", ") : "No metric names received"),
      ActivityMetric.new(key: :screen_context, label: "Screen context", value: screen_count, unit: "receipts", coverage: coverage(screen_count, total), detail: "#{screen_count}/#{total} non-error receipts supplied a screen")
    ]
  end

  def coverage(sampled, total)
    return :not_applicable if total.zero?
    return :not_collected if sampled.zero?
    return :complete if sampled == total

    :partial
  end
end
