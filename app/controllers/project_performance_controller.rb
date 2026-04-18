class ProjectPerformanceController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    @db_query_events = @project.ingest_events.recent_db_queries(24.hours.ago).to_a
    @db_stats = IngestEvent.db_stats_from_events(@db_query_events)
    @slow_db_queries = @db_query_events.sort_by { |event| -IngestEvent.duration_ms(event) }.first(20)
    @release_cards = IngestEvent.released_error_groups(@project, lookback: 45.days, limit: 6)
    @transaction_stats = IngestEvent.transaction_stats(@project, since: 24.hours.ago)
    @slow_transactions = IngestEvent.slow_transactions_with_errors(@project, since: 24.hours.ago, limit: 20)

    render "projects/performance"
  end
end
