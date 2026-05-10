class DashboardController < ApplicationController
  DASHBOARD_CACHE_TTL = 30.seconds
  MAX_EXPLORER_ENVIRONMENT_FILTER_LENGTH = 80

  before_action :authenticate_user!

  def index
    accessible = current_user.active_projects
    @projects = accessible.order(created_at: :desc).to_a
    project_ids = @projects.map(&:id)

    summary = safe_cache_fetch(
      [ "dashboard_summary", current_user.id, project_ids, cache_time_bucket(DASHBOARD_CACHE_TTL) ],
      expires_in: DASHBOARD_CACHE_TTL
    ) { Dashboard.summary_for(project_ids) }

    @project_stats = summary[:project_stats]
    @projects_count = summary[:projects_count]
    @api_keys_count = summary[:api_keys_count]
    @events_last_24h = summary[:events_last_24h]
    @events_by_type_last_24h = summary[:events_by_type_last_24h]
    @active_projects_count = summary[:active_project_ids_last_24h].size
    @quiet_projects_count = [ @projects_count - @active_projects_count, 0 ].max
    @open_error_groups_count = summary[:open_error_groups_count]
    @new_error_groups_last_24h = summary[:new_error_groups_last_24h]
    @projects_with_open_errors_count = summary[:projects_with_open_errors_count]
    @monitors_count = summary[:monitors_count]
    @monitor_status_counts = summary[:monitor_status_counts]
    @unhealthy_monitors_count = @monitor_status_counts.fetch(:missed, 0) + @monitor_status_counts.fetch(:error, 0)
    @recent_context_events = ordered_records(IngestEvent.includes(:project).where(id: summary[:recent_context_event_ids]), summary[:recent_context_event_ids])
    @recent_error_groups = ordered_records(ErrorGroup.includes(:project, :latest_event).where(id: summary[:recent_error_group_ids]), summary[:recent_error_group_ids])
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

    render json: dashboard_explorer_response(projects, explorer)
  end

  private

  def ordered_records(relation, ids)
    records_by_id = relation.index_by(&:id)
    ids.filter_map { |id| records_by_id[id] }
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

  def dashboard_explorer_response(projects, explorer)
    projects_by_id = projects.index_by(&:id)
    event_type_counts = explorer[:event_types] || {}

    {
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

  def dashboard_explorer_filters(project_ids)
    event_type = params[:event_type].to_s
    project_id = params[:project_id].to_i
    environment = params[:environment].to_s.strip.first(MAX_EXPLORER_ENVIRONMENT_FILTER_LENGTH)

    {}.tap do |filters|
      filters[:event_type] = event_type if IngestEvent.event_types.key?(event_type)
      filters[:project_id] = project_id if project_ids.include?(project_id)
      filters[:environment] = environment if environment.present?
    end
  end
end
