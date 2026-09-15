class ProjectEventsController < ApplicationController
  include ProjectEvidenceDownload
  include ProjectEventResponses
  include ProjectInboxData
  include ProjectEventDetailData

  before_action :authenticate_user!
  before_action :set_project
  before_action :set_event, only: %i[show original_evidence]
  before_action :require_project_manager, only: :original_evidence

  # GET /projects/:project_uuid/events   — Turbo Frame: project_inbox
  def index
    @filter        = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    @query         = params[:q].to_s.strip
    @assignee_filter = normalize_inbox_assignee_filter(@project, params[:assignee], viewer: current_user)
    @profile_filters = normalize_inbox_profile_filters(@project)
    @sort = normalize_inbox_sort(@project, params[:sort])
    @inbox_page    = inbox_page(@project, filter: @filter, query: @query, assignee: @assignee_filter, viewer: current_user, dimensions: @profile_filters, sort: @sort, cursor: params[:cursor])
    @groups        = @inbox_page.groups
    @next_cursor   = @inbox_page.next_cursor
    @latest_events = inbox_latest_events(@project, @groups, profile_filters: @profile_filters)
    @android_mapping_resolutions = inbox_android_mapping_resolutions(@project, @latest_events)
    @ios_symbol_coverages = inbox_ios_symbol_coverages(@project, @latest_events)
    @group_trends  = inbox_group_trends(@project, @groups, profile_filters: @profile_filters)
    @impact_summaries = inbox_impact_summaries(@project, @groups, profile_filters: @profile_filters)
    @evidence_signals = inbox_evidence_signals(@project, @groups, profile_filters: @profile_filters)
    @has_activity_events = @groups.empty? && project_has_activity_events?(@project)
    @selected_uuid = params[:group_uuid]
    render_inbox_response
  end

  # GET /projects/:project_uuid/events/:uuid   — Turbo Frame: error_detail
  def show
    @profile_filters = normalize_inbox_profile_filters(@project)
    occurrence_scope = if @event.error_group
      project_inbox_query(@project).occurrence_relation(@profile_filters, group_ids: [ @event.error_group_id ])
    end
    impact_baseline_scope = project_inbox_query(@project).occurrence_relation(@profile_filters) if occurrence_scope
    detail_data = build_project_event_detail(@project, @event, occurrence_scope: occurrence_scope, impact_baseline_scope: impact_baseline_scope)
    @group = detail_data[:group]
    @occurrences = detail_data[:occurrences]
    @related_logs = detail_data[:related_logs]
    @impact_summary = detail_data[:impact_summary]
    @variant_summary = detail_data[:variant_summary]

    @filter = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    @query  = params[:q].to_s.strip
    @assignee_filter = normalize_inbox_assignee_filter(@project, params[:assignee], viewer: current_user)
    @assignable_users = @project.assignable_users.to_a
    @tab    = ProjectExperience.for(@project).normalize_detail_tab(
      params[:tab],
      event: @event,
      occurrences_count: @occurrences.size,
      related_logs_count: @related_logs.size
    )
    @frame_scope = params[:frame_scope].presence_in(%w[application all]) || "application"
    @frame = params[:frame].to_i
    render_event_response
  end

  private

  def inbox_profile_redirect_params
    profile = ProjectExperience.for(@project)
    allowed = profile.filters.filter_map { |definition| definition.key.to_s } + [ "sort" ]
    params.to_unsafe_h.slice(*allowed).compact_blank
  end

  def set_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:project_uuid])
  end

  def set_event
    @event = project_event_lookup_scope.find_by!(uuid: params[:uuid])
  end

  def require_project_manager
    head :not_found unless @project.managed_by?(current_user)
  end

  def project_event_lookup_scope
    occurred_at = event_occurred_at_param
    return @project.ingest_events if occurred_at.blank?

    @project.ingest_events.where(occurred_at: occurred_at)
  end

  def event_occurred_at_param
    return if params[:event_occurred_at].blank?

    Time.zone.iso8601(params[:event_occurred_at].to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
