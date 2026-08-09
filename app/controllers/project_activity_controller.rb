class ProjectActivityController < ApplicationController
  include ProjectScope
  include TableCursorPagination

  ACTIVITY_EVENT_TYPES = %w[all metric log transaction check_in].freeze
  ACTIVITY_PERIODS = {
    "all" => nil,
    "24h" => 24.hours,
    "7d" => 7.days,
    "30d" => 30.days,
    "90d" => 90.days
  }.freeze
  PER_PAGE_OPTIONS = [ 25, 50, 100 ].freeze

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    @telemetry_scope = ProjectTelemetryScope.from(project: @project, source: params)
    @activity_scope_projection = @telemetry_scope.project_for(:activity)
    @insights_scope_projection = @telemetry_scope.project_for(:insights)
    @activity_filters = normalized_activity_filters
    @activity_event_type_options = activity_event_type_options
    @activity_period_options = activity_period_options
    @per_page_options = PER_PAGE_OPTIONS
    @activity_filters_active = activity_filters_active?(@activity_filters)
    @activity_page = cursor_page(
      filtered_activity_events,
      before: params[:before],
      after: params[:after],
      per_page: @activity_filters[:per_page],
      timestamp_column: mobile_activity? ? :created_at : :occurred_at
    )
    @activity_events = @activity_page.records
    @mobile_activity = ProjectExperience.for(@project).supports?(:mobile)
    @activity_related_groups = @mobile_activity ? related_activity_groups(@activity_events) : {}
    @activity_row_presenters = @activity_events.index_with do |event|
      ProjectActivity::RowPresenter.new(
        project: @project,
        event:,
        related_group: @activity_related_groups[ProjectActivity::RowPresenter.trace_id(event)]
      )
    end
    @activity_has_any_events = @project.ingest_events.where.not(event_type: :error).exists? if @activity_events.empty?

    render "projects/activity"
  end

  private

  def filtered_activity_events
    filters = @activity_filters
    scope = @project.ingest_events.where.not(event_type: :error)

    scope = scope.where(event_type: filters[:event_type]) unless filters[:event_type] == "all"
    scope = apply_activity_period_filter(scope, filters[:period])
    scope = apply_text_filter(scope, filters[:q]) if filters[:q].present?
    scope = scope.where("COALESCE(NULLIF(ingest_events.context->>'environment', ''), 'production') = ?", filters[:environment]) if filters[:environment].present?
    scope = scope.where("ingest_events.context->>'release' = ?", filters[:release]) if filters[:release].present?
    if mobile_activity?
      scope = scope.where("COALESCE(NULLIF(ingest_events.context #>> '{telemetry_evidence,source}', ''), NULLIF(ingest_events.context #>> '{diagnostic,source}', ''), 'sdk') = ?", filters[:source]) if filters[:source].present?
      scope = scope.where("COALESCE(NULLIF(ingest_events.context #>> '{telemetry_evidence,time,precision}', ''), 'unknown') = ?", filters[:time_precision]) if filters[:time_precision].present?
      scope = scope.where("ingest_events.context #>> '{app,version_code}' = ?", filters[:build_number]) if filters[:build_number].present?
      scope = scope.where("COALESCE(NULLIF(ingest_events.context #>> '{distribution,channel}', ''), ingest_events.context #>> '{distribution,track}') = ?", filters[:channel]) if filters[:channel].present?
      scope = scope.where("COALESCE(NULLIF(ingest_events.context->>'apple_platform', ''), ingest_events.context->>'platform') = ?", filters[:platform]) if filters[:platform].present?
    end
    scope
  end

  def normalized_activity_filters
    scope = @activity_scope_projection.params
    {
      event_type: params[:event_type].presence_in(ACTIVITY_EVENT_TYPES) || "all",
      period: (params[:period].presence || scope[:period]).presence_in(ACTIVITY_PERIODS.keys) || "24h",
      q: params[:q].to_s.strip,
      environment: (params[:environment].presence || scope[:environment]).to_s.strip,
      release: (params[:release].presence || scope[:release]).to_s.strip,
      source: mobile_activity? ? (params[:source].presence || scope[:source]).to_s.strip : "",
      time_precision: mobile_activity? ? params[:time_precision].to_s.strip : "",
      build_number: mobile_activity? ? (params[:build_number].presence || scope[:build_number]).to_s.strip : "",
      channel: mobile_activity? ? (params[:channel].presence || scope[:channel]).to_s.strip : "",
      platform: mobile_activity? ? (params[:platform].presence || scope[:platform]).to_s.strip.downcase : "",
      per_page: normalized_per_page(params[:per_page].presence || TableCursorPagination::DEFAULT_PER_PAGE)
    }
  end

  def apply_period_filter(scope, period, periods)
    lookback = periods.fetch(period)
    return scope if lookback.blank?

    scope.where("ingest_events.occurred_at >= ?", lookback.ago)
  end

  def apply_activity_period_filter(scope, period)
    lookback = ACTIVITY_PERIODS.fetch(period)
    return scope if lookback.blank?

    column = mobile_activity? ? "ingest_events.created_at" : "ingest_events.occurred_at"
    scope.where("#{column} >= ?", lookback.ago)
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

  def activity_filters_active?(filters)
    filters[:event_type] != "all" ||
      filters[:period] != "24h" ||
      filters[:q].present? ||
      filters[:environment].present? ||
      filters[:release].present? ||
      filters[:source].present? ||
      filters[:time_precision].present? ||
      filters[:build_number].present? ||
      filters[:channel].present? ||
      filters[:platform].present?
  end

  def activity_event_type_options
    [
      [ "All types", "all" ],
      [ "Metrics", "metric" ],
      [ "Logs", "log" ],
      [ "Transactions", "transaction" ],
      [ "Check-ins", "check_in" ]
    ]
  end

  def activity_period_options
    [
      [ "All time", "all" ],
      [ "24 hours", "24h" ],
      [ "7 days", "7d" ],
      [ "30 days", "30d" ],
      [ "90 days", "90d" ]
    ]
  end

  def mobile_activity?
    ProjectExperience.for(@project).supports?(:mobile)
  end

  def related_activity_groups(events)
    trace_ids = events.filter_map { |event| ProjectActivity::RowPresenter.trace_id(event) }.uniq
    return {} if trace_ids.empty?

    occurred_times = events.map(&:occurred_at).compact
    scope = @project.ingest_events
      .where(event_type: :error)
      .where.not(error_group_id: nil)
      .where(
        "ingest_events.context->>'trace_id' IN (?) OR ingest_events.context #>> '{trace,id}' IN (?)",
        trace_ids,
        trace_ids
      )
    if occurred_times.any?
      scope = scope.where(occurred_at: (occurred_times.min - 1.day)..(occurred_times.max + 1.day))
    end

    scope.order(created_at: :desc).limit([ trace_ids.size * 3, 300 ].min).includes(:error_group).each_with_object({}) do |error_event, result|
      trace_id = ProjectActivity::RowPresenter.trace_id(error_event)
      result[trace_id] ||= error_event.error_group if trace_id.present?
    end
  end
end
