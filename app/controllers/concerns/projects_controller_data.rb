# frozen_string_literal: true

module ProjectsControllerData
  extend ActiveSupport::Concern

  private

  def render_project_inbox
    @filter = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    @query  = params[:q].to_s.strip
    @assignee_filter = normalize_inbox_assignee_filter(@project, params[:assignee], viewer: current_user)
    @profile_filters = normalize_inbox_profile_filters(@project)
    @sort = normalize_inbox_sort(@project, params[:sort])
    @profile_filter_options = inbox_filter_options(@project)
    @assignable_users = @project.assignable_users.to_a
    @tab    = ProjectExperience.for(@project).normalize_detail_tab(params[:tab])
    @inbox_page = inbox_page(@project, filter: @filter, query: @query, assignee: @assignee_filter, viewer: current_user, dimensions: @profile_filters, sort: @sort, cursor: params[:cursor])
    @groups = @inbox_page.groups
    @next_cursor = @inbox_page.next_cursor
    @latest_events = inbox_latest_events(@project, @groups, profile_filters: @profile_filters)
    @android_mapping_resolutions = inbox_android_mapping_resolutions(@project, @latest_events)
    @ios_symbol_coverages = inbox_ios_symbol_coverages(@project, @latest_events)
    @impact_summaries = inbox_impact_summaries(@project, @groups, profile_filters: @profile_filters)
    @evidence_signals = inbox_evidence_signals(@project, @groups, profile_filters: @profile_filters)
    @has_activity_events = @groups.empty? && project_has_activity_events?(@project)

    if turbo_frame_request? && request.headers["Turbo-Frame"] == "project_inbox"
      @selected_uuid = params[:group_uuid]
      return render partial: "projects/inbox_table", locals: {
        project:       @project,
        groups:        @groups,
        latest_events: @latest_events,
        android_mapping_resolutions: @android_mapping_resolutions,
        ios_symbol_coverages: @ios_symbol_coverages,
        group_trends:  inbox_group_trends(@project, @groups, profile_filters: @profile_filters),
        impact_summaries: @impact_summaries,
        evidence_signals: @evidence_signals,
        has_activity_events: @has_activity_events,
        selected_uuid: @selected_uuid,
        filter:        @filter,
        query:         @query,
        assignee:      @assignee_filter,
        sort:          @sort,
        profile_filters: @profile_filters,
        next_cursor:   @next_cursor
      }
    end

    @counts  = inbox_counts(@project, assignee: @assignee_filter, viewer: current_user)
    @group_trends = inbox_group_trends(@project, @groups, profile_filters: @profile_filters)
    @selected_group = selected_inbox_group
    @selected_event = selected_inbox_event
    @selected_event = nil if selected_event_mismatches_scope?

    load_inbox_detail
    render :inbox unless performed?
  end

  def legacy_inbox_request?
    (request.query_parameters.keys & self.class::LEGACY_INBOX_PARAMS).any?
  end

  def project_create_params
    params.require(:project).permit(
      :name,
      :description,
      :integration_kind,
      retention_policy_attributes: [
        :hot_retention_days,
        :trace_retention_days,
        :error_retention_days,
        :archive_enabled,
        :archive_before_delete
      ]
    )
  end

  def project_update_params
    params.require(:project).permit(:name, :description)
  end

  def retention_policy_attributes_missing?
    params.dig(:project, :retention_policy_attributes).blank?
  end

  def build_default_retention_policy
    @project.build_retention_policy(
      hot_retention_days: ProjectRetentionPolicy::DEFAULT_HOT_RETENTION_DAYS,
      trace_retention_days: ProjectRetentionPolicy::DEFAULT_TRACE_RETENTION_DAYS,
      error_retention_days: ProjectRetentionPolicy::DEFAULT_ERROR_RETENTION_DAYS
    ) unless @project.retention_policy
  end

  def filtered_projects(scope, filter)
    case filter
    when "archived" then scope.archived
    when "all" then scope
    else scope.active
    end
  end

  def project_filter_counts(scope)
    {
      active: scope.active.count,
      archived: scope.archived.count,
      all: scope.count
    }
  end

  def cached_project_stats(project_ids)
    cache_key = [ "projects_stats", current_user.id, project_ids, cache_time_bucket(self.class::PROJECT_STATS_CACHE_TTL) ]
    safe_cache_fetch(cache_key, expires_in: self.class::PROJECT_STATS_CACHE_TTL) { Project.stats_for(project_ids) }
  end

  def projects_overview(projects, project_stats)
    stats = projects.filter_map { |project| project_stats[project.id] }
    active_projects_count = stats.count { |project| project[:received_events].to_i.positive? }

    {
      projects_count: projects.size,
      open_groups_count: stats.sum { |project| project[:open_groups].to_i },
      activity_events_count: stats.sum { |project| project[:activity_events].to_i },
      received_events_count: stats.sum { |project| project[:received_events].to_i },
      active_projects_count: active_projects_count,
      quiet_projects_count: [ projects.size - active_projects_count, 0 ].max
    }
  end

  def project_dashboard_metrics(project)
    safe_cache_fetch(
      [ "project", project.id, "dashboard_metrics", cache_time_bucket(self.class::PROJECT_DASHBOARD_CACHE_TTL) ],
      expires_in: self.class::PROJECT_DASHBOARD_CACHE_TTL
    ) do
      since = 24.hours.ago
      db_query_events = project.ingest_events.recent_db_queries(since).select(:id, :context).to_a

      {
        db_stats: IngestEvent.db_stats_from_events(db_query_events),
        transaction_stats: IngestEvent.transaction_stats(project, since: since)
      }
    end
  end

  def selected_inbox_group
    if params[:group_uuid].present?
      @groups.find { |group| group.uuid == params[:group_uuid] }
    else
      @groups.first
    end
  end

  def selected_inbox_event
    return if params[:event_uuid].blank?

    @project.ingest_events.find_by(uuid: params[:event_uuid])
  end

  def selected_event_mismatches_scope?
    return false unless @selected_event
    return true unless @selected_group && @selected_event.error_group_id == @selected_group.id

    project_inbox_query(@project)
      .occurrence_relation(@profile_filters, group_ids: [ @selected_group.id ])
      .where(ingest_event_id: @selected_event.id, ingest_event_occurred_at: @selected_event.occurred_at)
      .none?
  end

  def load_inbox_detail
    detail_event = @selected_event || @latest_events[@selected_group&.id]
    return if detail_event.blank?

    occurrence_scope = project_inbox_query(@project).occurrence_relation(@profile_filters, group_ids: [ @selected_group.id ])
    impact_baseline_scope = project_inbox_query(@project).occurrence_relation(@profile_filters)
    detail_data = build_project_event_detail(
      @project,
      detail_event,
      group: @selected_group,
      occurrence_scope: occurrence_scope,
      impact_baseline_scope: impact_baseline_scope,
      preloaded_impact_summary: @impact_summaries[@selected_group.id]
    )
    @detail_event = detail_data[:event]
    @detail_group = detail_data[:group]
    @detail_occurrences = detail_data[:occurrences]
    @detail_related_logs = detail_data[:related_logs]
    @detail_impact_summary = detail_data[:impact_summary]
    @detail_variant_summary = detail_data[:variant_summary]
  end
end
