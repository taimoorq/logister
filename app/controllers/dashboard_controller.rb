class DashboardController < ApplicationController
  DASHBOARD_CACHE_TTL = 30.seconds

  include DashboardExplorerFiltering

  before_action :authenticate_user!

  def index
    accessible = current_user.active_projects
    @projects = accessible.order(created_at: :desc).to_a
    project_ids = @projects.map(&:id)

    summary = safe_cache_fetch(
      [ "dashboard_summary", current_user.id, project_ids, cache_time_bucket(DASHBOARD_CACHE_TTL) ],
      expires_in: DASHBOARD_CACHE_TTL
    ) { Dashboard.summary_for(project_ids, viewer: current_user) }

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
    @recent_context_events = ordered_records(IngestEvent.includes(:project).where(id: summary[:recent_context_event_ids]), summary[:recent_context_event_ids])
    @recent_error_groups = ordered_records(ErrorGroup.includes(:project).where(id: summary[:recent_error_group_ids]), summary[:recent_error_group_ids])
    @recent_error_group_latest_events = latest_events_for(@recent_error_groups)
    @assigned_error_groups = ordered_records(ErrorGroup.includes(:project).where(id: summary[:assigned_error_group_ids]), summary[:assigned_error_group_ids])
    @project_summaries = ranked_project_summaries(@projects, @project_stats).first(6)
    @dashboard_explorer = dashboard_explorer_config(@projects)
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

  private

  def ordered_records(relation, ids)
    records_by_id = relation.index_by(&:id)
    ids.filter_map { |id| records_by_id[id] }
  end

  def latest_events_for(groups)
    latest_event_ids = groups.filter_map(&:latest_event_id)
    return {} if latest_event_ids.empty?

    IngestEvent.where(id: latest_event_ids)
               .select(:id, :project_id, :uuid, :message)
               .index_by(&:id)
  end

  def ranked_project_summaries(projects, project_stats)
    projects.to_a.sort_by do |project|
      stats = project_stats[project.id] || {}
      [
        stats.fetch(:open_groups, 0).to_i.positive? ? 0 : 1,
        -stats.fetch(:open_groups, 0).to_i,
        -(stats[:latest_event_at]&.to_i || 0),
        -project.created_at.to_i
      ]
    end
  end

  def dashboard_explorer_config(projects)
    {
      endpoint: dashboard_explorer_path,
      events_endpoint: dashboard_events_path,
      window_days: Dashboard::EXPLORER_WINDOW_DAYS,
      event_types: Dashboard::EVENT_TYPE_ORDER.map do |event_type|
        { key: event_type, label: helpers.dashboard_event_type_label(event_type) }
      end,
      projects: projects.map do |project|
        {
          id: project.id,
          name: project.name,
          slug: project.slug,
          integration: project.integration_label,
          url: project_path(project),
          activity_url: activity_project_path(project)
        }
      end
    }
  end

  def dashboard_explorer_response(projects, explorer, filters)
    projects_by_id = projects.index_by(&:id)
    event_type_counts = explorer[:event_types] || {}

    {
      events_url: dashboard_events_path(dashboard_explorer_query_params(filters)),
      window_started_at: explorer[:window_started_at],
      window_days: explorer[:window_days],
      days: explorer[:days],
      totals: explorer[:totals],
      timeline: explorer[:timeline],
      event_types: Dashboard::EVENT_TYPE_ORDER.map do |event_type|
        {
          key: event_type,
          label: helpers.dashboard_event_type_label(event_type),
          count: event_type_counts.fetch(event_type, 0).to_i
        }
      end,
      projects: explorer[:projects].filter_map do |project_row|
        project = projects_by_id[project_row[:project_id]]
        next if project.blank?

        {
          id: project.id,
          name: project.name,
          slug: project.slug,
          integration: project.integration_label,
          url: project_path(project),
          activity_url: activity_project_path(project),
          count: project_row[:count],
          open_errors: project_row[:open_errors]
        }
      end,
      environments: explorer[:environments]
    }
  end
end
