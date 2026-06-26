# frozen_string_literal: true

module DashboardPageData
  extend ActiveSupport::Concern

  private

  def dashboard_summary_options
    if @dashboard_tab == "projects"
      {
        include_assignments: false,
        include_context_events: false,
        include_project_signals: true,
        include_project_stats: true,
        recent_error_group_limit: 1
      }
    else
      {
        include_assignments: true,
        include_context_events: true,
        include_project_signals: false,
        include_project_stats: false,
        recent_error_group_limit: 6
      }
    end
  end

  def load_overview_dashboard_data(summary)
    recent_context_event_refs = summary[:recent_context_event_refs] || summary[:recent_context_event_ids].map { |id| { id: id } }
    @recent_context_events = ordered_records(
      IngestEvent.for_partition_references(recent_context_event_refs, id_key: :id, occurred_at_key: :occurred_at).includes(:project),
      recent_context_event_refs.pluck(:id)
    )
    @recent_error_groups = ordered_records(ErrorGroup.includes(:project).where(id: summary[:recent_error_group_ids]), summary[:recent_error_group_ids])
    @recent_error_group_latest_events = latest_events_for(@recent_error_groups)
    @assigned_error_groups = ordered_records(ErrorGroup.includes(:project).where(id: summary[:assigned_error_group_ids]), summary[:assigned_error_group_ids])
    @dashboard_explorer = dashboard_explorer_config(@projects)
  end

  def load_projects_dashboard_data(summary)
    @recent_error_groups = ordered_records(ErrorGroup.includes(:project).where(id: summary[:recent_error_group_ids]), summary[:recent_error_group_ids])
    @project_summaries = ranked_project_summaries(@projects, @project_stats).first(6)
  end

  def ordered_records(relation, ids)
    records_by_id = relation.index_by(&:id)
    ids.filter_map { |id| records_by_id[id] }
  end

  def latest_events_for(groups)
    IngestEvent.for_partition_references(
               groups,
               id_key: :latest_event_id,
               occurred_at_key: :latest_event_occurred_at
               )
               .select(:id, :project_id, :uuid, :message, :occurred_at)
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
