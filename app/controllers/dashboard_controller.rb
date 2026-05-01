class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    accessible = current_user.accessible_projects
    project_ids = accessible.pluck(:id)

    @projects = accessible.order(created_at: :desc)
    @project_stats = if project_ids.any?
      safe_cache_fetch(
        [ "dashboard_project_stats", current_user.id, Project.stats_cache_version(project_ids) ],
        expires_in: 45.seconds
      ) { Project.stats_for(project_ids) }
    else
      {}
    end

    summary = safe_cache_fetch(
      [ "dashboard_summary", current_user.id, Dashboard.cache_version(project_ids) ],
      expires_in: 30.seconds
    ) { Dashboard.summary_for(project_ids) }

    @projects_count = summary[:projects_count]
    @api_keys_count = summary[:api_keys_count]
    @events_last_24h = summary[:events_last_24h]
  end
end
