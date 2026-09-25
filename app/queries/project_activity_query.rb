# frozen_string_literal: true

class ProjectActivityQuery
  def initialize(project:, filters:, lookback:)
    @project = project
    @filters = filters
    @lookback = lookback
  end

  def events
    scope = project.ingest_events.where.not(event_type: :error)

    scope = scope.where(event_type: filters[:event_type]) unless filters[:event_type] == "all"
    scope = apply_activity_period_filter(scope)
    scope = apply_text_filter(scope, filters[:q]) if filters[:q].present?
    scope = scope.where("COALESCE(NULLIF(ingest_events.context->>'environment', ''), 'production') = ?", filters[:environment]) if filters[:environment].present?
    scope = scope.for_release(filters[:release]) if filters[:release].present?
    if mobile_activity?
      scope = scope.where("COALESCE(NULLIF(ingest_events.context #>> '{telemetry_evidence,source}', ''), NULLIF(ingest_events.context #>> '{diagnostic,source}', ''), 'sdk') = ?", filters[:source]) if filters[:source].present?
      scope = scope.where("COALESCE(NULLIF(ingest_events.context #>> '{telemetry_evidence,time,precision}', ''), 'unknown') = ?", filters[:time_precision]) if filters[:time_precision].present?
      scope = scope.where("ingest_events.context #>> '{app,version_code}' = ?", filters[:build_number]) if filters[:build_number].present?
      scope = scope.where("COALESCE(NULLIF(ingest_events.context #>> '{distribution,channel}', ''), ingest_events.context #>> '{distribution,track}') = ?", filters[:channel]) if filters[:channel].present?
      scope = scope.where("COALESCE(NULLIF(ingest_events.context->>'apple_platform', ''), ingest_events.context->>'platform') = ?", filters[:platform]) if filters[:platform].present?
    end
    scope
  end

  def related_groups(events)
    trace_ids = events.filter_map { |event| ProjectActivity::RowPresenter.trace_id(event) }.uniq
    return {} if trace_ids.empty?

    occurred_times = events.map(&:occurred_at).compact
    scope = project.ingest_events
      .where(event_type: :error)
      .where.not(error_group_id: nil)

    scope = trace_ids.reduce(scope.none) do |matches, trace_id|
      matches.or(CorrelationContext.filter(scope, "trace_id", value: trace_id))
    end
    if occurred_times.any?
      scope = scope.where(occurred_at: (occurred_times.min - 1.day)..(occurred_times.max + 1.day))
    end

    scope.order(created_at: :desc).limit([ trace_ids.size * 3, 300 ].min).includes(:error_group).each_with_object({}) do |error_event, result|
      trace_id = ProjectActivity::RowPresenter.trace_id(error_event)
      result[trace_id] ||= error_event.error_group if trace_id.present?
    end
  end

  private

  def apply_activity_period_filter(scope)
    return scope if lookback.blank?

    column = mobile_activity? ? :created_at : :occurred_at
    scope.where(column => lookback.ago..)
  end

  def apply_text_filter(scope, query)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    scope.where(
      <<~SQL.squish,
        LOWER(ingest_events.message) LIKE :term
        OR LOWER(COALESCE(ingest_events.level, '')) LIKE :term
        OR LOWER(COALESCE(
          ingest_events.context->>'transaction_name',
          ingest_events.context->>'transactionName',
          ingest_events.context->>'name',
          ingest_events.context->>'check_in_slug',
          ingest_events.context->>'logger_name',
          ingest_events.context->>'release',
          ''
        )) LIKE :term
      SQL
      term: term
    )
  end

  attr_reader :project, :filters, :lookback

  def mobile_activity?
    ProjectExperience.for(project).supports?(:mobile)
  end
end
