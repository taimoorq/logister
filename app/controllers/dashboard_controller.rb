class DashboardController < ApplicationController
  DASHBOARD_CACHE_TTL = 30.seconds

  include DashboardExplorerFiltering
  include DashboardPageData

  before_action :authenticate_user!

  def index
    @dashboard_tab = params[:tab].presence_in(%w[overview projects]) || "overview"
    accessible = current_user.active_projects
    @projects = accessible.order(created_at: :desc).to_a
    project_ids = @projects.map(&:id)

    summary = safe_cache_fetch(
      [ "dashboard_summary", current_user.id, @dashboard_tab, project_ids, cache_time_bucket(DASHBOARD_CACHE_TTL) ],
      expires_in: DASHBOARD_CACHE_TTL
    ) { Dashboard.summary_for(project_ids, viewer: current_user, **dashboard_summary_options) }

    @project_stats = summary[:project_stats]
    @projects_count = summary[:projects_count]
    @api_keys_count = summary[:api_keys_count]
    @events_last_24h = summary[:events_last_24h]
    @events_by_type_last_24h = summary[:events_by_type_last_24h]
    @active_projects_count = summary[:active_project_ids_last_24h].size
    @quiet_projects_count = [ @projects_count - @active_projects_count, 0 ].max
    @open_error_groups_count = summary[:open_error_groups_count]
    @assigned_error_groups_count = summary[:assigned_error_groups_count]
    @projects_with_assigned_errors_count = summary[:projects_with_assigned_errors_count]
    @unassigned_error_groups_count = summary[:unassigned_error_groups_count]
    @projects_with_unassigned_errors_count = summary[:projects_with_unassigned_errors_count]
    @new_error_groups_last_24h = summary[:new_error_groups_last_24h]
    @projects_with_open_errors_count = summary[:projects_with_open_errors_count]
    @monitors_count = summary[:monitors_count]
    @monitor_status_counts = summary[:monitor_status_counts]
    @unhealthy_monitors_count = @monitor_status_counts.fetch(:missed, 0) + @monitor_status_counts.fetch(:error, 0)

    if @dashboard_tab == "overview"
      load_overview_dashboard_data(summary)
    else
      load_projects_dashboard_data(summary)
    end
  end

  def explorer
    projects = current_user.active_projects.order(created_at: :desc).to_a
    project_ids = projects.map(&:id)
    filters = dashboard_explorer_filters(project_ids)
    explorer = safe_cache_fetch(
      [ "dashboard_explorer", current_user.id, project_ids, filters, cache_time_bucket(DASHBOARD_CACHE_TTL) ],
      expires_in: DASHBOARD_CACHE_TTL
    ) { Dashboard.explorer_for(project_ids, **filters) }

    render json: dashboard_explorer_response(projects, explorer, filters)
  end
end
