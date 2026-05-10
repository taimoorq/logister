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
    @events_by_type_last_24h = summary[:events_by_type_last_24h]
    @active_projects_count = summary[:active_project_ids_last_24h].size
    @quiet_projects_count = [ @projects_count - @active_projects_count, 0 ].max
    @open_error_groups_count = summary[:open_error_groups_count]
    @new_error_groups_last_24h = summary[:new_error_groups_last_24h]
    @projects_with_open_errors_count = summary[:projects_with_open_errors_count]
    @monitors_count = summary[:monitors_count]
    @monitor_status_counts = summary[:monitor_status_counts]
    @unhealthy_monitors_count = @monitor_status_counts.fetch(:missed, 0) + @monitor_status_counts.fetch(:error, 0)
    @recent_events = ordered_records(IngestEvent.includes(:project).where(id: summary[:recent_event_ids]), summary[:recent_event_ids]).first(8)
    @recent_error_groups = ordered_records(ErrorGroup.includes(:project, :latest_event).where(id: summary[:recent_error_group_ids]), summary[:recent_error_group_ids])
    @project_summaries = ranked_project_summaries(@projects, @project_stats).first(6)
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
end
