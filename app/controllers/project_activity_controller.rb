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
      activity_query.events,
      before: params[:before],
      after: params[:after],
      per_page: @activity_filters[:per_page],
      timestamp_column: mobile_activity? ? :created_at : :occurred_at
    )
    @activity_events = @activity_page.records
    @mobile_activity = ProjectExperience.for(@project).supports?(:mobile)
    @activity_related_groups = @mobile_activity ? activity_query.related_groups(@activity_events) : {}
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

  def activity_query
    @activity_query ||= ProjectActivityQuery.new(
      project: @project, filters: @activity_filters, lookback: ACTIVITY_PERIODS.fetch(@activity_filters[:period])
    )
  end

  def mobile_activity?
    ProjectExperience.for(@project).supports?(:mobile)
  end
end
