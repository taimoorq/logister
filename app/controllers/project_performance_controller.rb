class ProjectPerformanceController < ApplicationController
  include ProjectScope

  FRAME_IDS = {
    request_breakdown: "performance_request_breakdown",
    database_load: "performance_database_load",
    release_health: "performance_release_health",
    transactions: "performance_transactions"
  }.freeze

  before_action :authenticate_user!
  before_action :set_accessible_project
  before_action :require_server_performance!, only: FRAME_IDS.keys
  before_action :require_registered_performance_frame, only: FRAME_IDS.keys

  def show
    if mobile_project?
      @mobile_app_health = ProjectMobileAppHealth.new(@project).call
      render "projects/performance"
      return
    end

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

  def mobile_project?
    @project.integration_android? || @project.integration_ios?
  end

  def require_server_performance!
    return unless mobile_project?

    redirect_to performance_project_path(@project), status: :see_other, alert: "Request and database panels do not apply to this mobile app-health view."
  end

  def require_registered_performance_frame
    expected_frame_id = FRAME_IDS.fetch(action_name.to_sym)

    unless turbo_frame_request?
      redirect_to performance_project_path(
        @project,
        **request.query_parameters.symbolize_keys,
        anchor: expected_frame_id
      )
      return
    end

    return if request.headers["Turbo-Frame"] == expected_frame_id

    head :unprocessable_content
  end

  def transaction_browser
    @transaction_browser ||= ProjectTransactionsBrowser.new(project: @project, params: params)
  end
end
