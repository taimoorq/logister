class ProjectEventsController < ApplicationController
  include ProjectInboxData

  before_action :authenticate_user!
  before_action :set_project
  before_action :set_event, only: :show

  # GET /projects/:project_uuid/events   — Turbo Frame: project_inbox
  def index
    @filter        = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    @query         = params[:q].to_s.strip
    @groups        = inbox_groups(@project, filter: @filter, query: @query)
    @selected_uuid = params[:group_uuid]

    if turbo_frame_request?
      render partial: "projects/inbox_table", locals: {
        project:       @project,
        groups:        @groups,
        selected_uuid: @selected_uuid,
        filter:        @filter,
        query:         @query
      }
    else
      redirect_to project_path(@project, filter: @filter, q: @query, group_uuid: @selected_uuid)
    end
  end

  # GET /projects/:project_uuid/events/:uuid   — Turbo Frame: error_detail
  def show
    @group       = @event.error_group
    @occurrences = @group&.error_occurrences
                         &.includes(:ingest_event)
                         &.recent_first
                         &.limit(50) || []

    @filter = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    @query  = params[:q].to_s.strip

    if turbo_frame_request?
      render partial: "project_events/event_detail", locals: {
        project:     @project,
        event:       @event,
        group:       @group,
        occurrences: @occurrences,
        filter:      @filter,
        query:       @query
      }
    else
      # Full page load (e.g. direct URL, page refresh after Turbo advance).
      # Redirect to the project workbench with the group pre-selected.
      # Use "all" filter so the group is visible in the inbox regardless of status.
      redirect_to project_path(
        @project,
        group_uuid: @group&.uuid,
        filter:     @group ? group_inbox_filter(@group) : @filter,
        q:          @query
      )
    end
  end

  private

  def set_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:project_uuid])
  end

  def set_event
    @event = @project.ingest_events.find_by!(uuid: params[:uuid])
  end

  # Pick the inbox filter tab that will actually show this group so the
  # workbench doesn't land on "unresolved" while the group is resolved/ignored.
  def group_inbox_filter(group)
    case group.status
    when "resolved" then "resolved"
    when "ignored"  then "ignored"
    when "archived" then "archived"
    else "unresolved"
    end
  end
end
