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
    @activity_filters = normalized_activity_filters
    @activity_event_type_options = activity_event_type_options
    @activity_period_options = activity_period_options
    @per_page_options = PER_PAGE_OPTIONS
    @activity_filters_active = activity_filters_active?(@activity_filters)
    @activity_page = cursor_page(
      filtered_activity_events,
      before: params[:before],
      after: params[:after],
      per_page: @activity_filters[:per_page]
    )
    @activity_events = @activity_page.records

    render "projects/activity"
  end

  private

  def filtered_activity_events
    filters = @activity_filters
    scope = @project.ingest_events.where.not(event_type: :error)

    scope = scope.where(event_type: filters[:event_type]) unless filters[:event_type] == "all"
    scope = apply_period_filter(scope, filters[:period], ACTIVITY_PERIODS)
    scope = apply_text_filter(scope, filters[:q]) if filters[:q].present?
    scope = scope.where("COALESCE(NULLIF(ingest_events.context->>'environment', ''), 'production') = ?", filters[:environment]) if filters[:environment].present?
    scope = scope.where("ingest_events.context->>'release' = ?", filters[:release]) if filters[:release].present?
    scope
  end

  def normalized_activity_filters
    {
      event_type: params[:event_type].presence_in(ACTIVITY_EVENT_TYPES) || "all",
      period: params[:period].presence_in(ACTIVITY_PERIODS.keys) || "24h",
      q: params[:q].to_s.strip,
      environment: params[:environment].to_s.strip,
      release: params[:release].to_s.strip,
      per_page: normalized_per_page(params[:per_page].presence || TableCursorPagination::DEFAULT_PER_PAGE)
    }
  end

  def apply_period_filter(scope, period, periods)
    lookback = periods.fetch(period)
    return scope if lookback.blank?

    scope.where("ingest_events.occurred_at >= ?", lookback.ago)
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
      filters[:release].present?
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
end
