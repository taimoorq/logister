class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    accessible = current_user.accessible_projects
    project_ids = accessible.pluck(:id)

    @projects = accessible.order(created_at: :desc).limit(6)
    summary = safe_cache_fetch(
      [ "dashboard_summary", current_user.id, Dashboard.cache_version(project_ids) ],
      expires_in: 30.seconds
    ) { Dashboard.summary_for(project_ids) }

    @projects_count = summary[:projects_count]
    @api_keys_count = summary[:api_keys_count]
    @events_last_24h = summary[:events_last_24h]
    @recent_events = IngestEvent.where(id: summary[:recent_event_ids]).includes(:project).order(occurred_at: :desc)
    error_events = IngestEvent.where(id: summary[:error_event_ids]).includes(:project).order(occurred_at: :desc)
    @error_views = IngestEvent.dashboard_error_views(error_events)
  end
end
