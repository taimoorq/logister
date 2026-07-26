class ProjectEventsController < ApplicationController
  include ProjectInboxData
  include ProjectEventDetailData

  before_action :authenticate_user!
  before_action :set_project
  before_action :set_event, only: :show

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
    @latest_events = inbox_latest_events(@groups)
    @group_trends  = inbox_group_trends(@project, @groups)
    @impact_summaries = inbox_impact_summaries(@project, @groups)
    @has_activity_events = @groups.empty? && project_has_activity_events?(@project)
    @selected_uuid = params[:group_uuid]

    if turbo_frame_request?
      render partial: "projects/inbox_table", locals: {
        project:       @project,
        groups:        @groups,
        latest_events: @latest_events,
        group_trends:  @group_trends,
        impact_summaries: @impact_summaries,
        has_activity_events: @has_activity_events,
        selected_uuid: @selected_uuid,
        filter:        @filter,
        query:         @query,
        assignee:      @assignee_filter,
        sort:          @sort,
        profile_filters: @profile_filters,
        next_cursor:   @next_cursor
      }
    else
      redirect_to inbox_project_path(@project, inbox_profile_redirect_params.merge(filter: @filter, q: @query, assignee: @assignee_filter, group_uuid: @selected_uuid))
    end
  end

  # GET /projects/:project_uuid/events/:uuid   — Turbo Frame: error_detail
  def show
    detail_data = build_project_event_detail(@project, @event)
    @group = detail_data[:group]
    @occurrences = detail_data[:occurrences]
    @related_logs = detail_data[:related_logs]
    @impact_summary = detail_data[:impact_summary]

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

    if turbo_frame_request? && request.headers["Turbo-Frame"] == "stack_frame_source" && @project.integration_ruby?
      render partial: "project_events/ruby_stack_frame_source", locals: {
        project:     @project,
        event:       @event,
        group:       @group,
        filter_param: @filter,
        query_param: @query,
        assignee_param: @assignee_filter,
        frame_scope: @frame_scope,
        selected_frame_index: @frame
      }
    elsif turbo_frame_request?
      render partial: "project_events/event_detail", locals: {
        project:     @project,
        event:       @event,
        group:       @group,
        occurrences: @occurrences,
        related_logs: @related_logs,
        impact_summary: @impact_summary,
        filter:      @filter,
        query:       @query,
        assignee:    @assignee_filter,
        assignable_users: @assignable_users,
        tab:         @tab,
        frame_scope: @frame_scope,
        frame:       @frame
      }
    else
      # Fallback: if this came from the project inbox workflow, keep users in that workbench.
      if params[:group_uuid].present? || params[:filter].present? || params[:q].present?
        redirect_to inbox_project_path(
          @project,
          inbox_profile_redirect_params.merge(
            filter: @filter,
            q: @query,
            assignee: @assignee_filter,
            group_uuid: @group&.uuid || params[:group_uuid],
            event_uuid: @event.uuid,
            tab: @tab
          )
        )
      else
        # Full page load — standalone event page.
        render :show
      end
    end
  end

  private

  def inbox_profile_redirect_params
    profile = ProjectExperience.for(@project)
    allowed = profile.filters.map { |definition| definition.key.to_s } + [ "sort" ]
    params.to_unsafe_h.slice(*allowed).compact_blank
  end

  def set_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:project_uuid])
  end

  def set_event
    @event = project_event_lookup_scope.find_by!(uuid: params[:uuid])
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
