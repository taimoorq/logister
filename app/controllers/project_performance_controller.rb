class ProjectPerformanceController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    @transaction_frame_params = transaction_browser.frame_params

    render "projects/performance"
  end

  def request_breakdown
    @request_breakdown = ProjectPerformance.request_breakdown(@project, since: 24.hours.ago)

    render partial: "projects/performance_request_breakdown", locals: { tour_group: "project-performance" }
  end

  def database_load
    @db_query_events = @project.ingest_events.recent_db_queries(24.hours.ago).to_a
    @db_stats = IngestEvent.db_stats_from_events(@db_query_events)

    render partial: "projects/performance_database_load"
  end

  def release_health
    @release_cards = IngestEvent.released_error_groups(@project, lookback: 45.days, limit: 6)

    render partial: "projects/performance_release_health"
  end

  def transactions
    @transaction_stats = IngestEvent.transaction_stats(@project, since: 24.hours.ago)
    @transaction_filters = transaction_browser.filters
    @transaction_period_options = transaction_browser.period_options
    @transaction_status_options = transaction_browser.status_options
    @per_page_options = transaction_browser.per_page_options
    @transaction_filters_active = transaction_browser.filters_active?
    @transaction_page = transaction_browser.page
    @transaction_rows = transaction_browser.rows

    render partial: "projects/performance_transactions", locals: { tour_group: "project-performance" }
  end

  private

  def transaction_browser
    @transaction_browser ||= ProjectTransactionsBrowser.new(project: @project, params: params)
  end
end
