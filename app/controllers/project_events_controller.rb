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
    @related_logs = IngestEvent.related_logs(project: @project, event: @event, window: 5.minutes, limit: 50)

    @filter = params[:filter].presence_in(ProjectInboxData::INBOX_FILTERS) || "unresolved"
    @query  = params[:q].to_s.strip
    @tab    = params[:tab].presence_in(%w[stacktrace context occurrences related_logs]) || "stacktrace"

    if turbo_frame_request?
      render partial: "project_events/event_detail", locals: {
        project:     @project,
        event:       @event,
        group:       @group,
        occurrences: @occurrences,
        related_logs: @related_logs,
        filter:      @filter,
        query:       @query,
        tab:         @tab
      }
    else
      # Fallback: if this came from the project inbox workflow, keep users in that workbench.
      if params[:group_uuid].present? || params[:filter].present? || params[:q].present?
        redirect_to project_path(
          @project,
          filter: @filter,
          q: @query,
          group_uuid: @group&.uuid || params[:group_uuid],
          event_uuid: @event.uuid,
          tab: @tab
        )
      else
        # Full page load — standalone event page.
        render :show
      end
    end
  end

  private

  def set_project
    @project = current_user.accessible_projects.find_by!(uuid: params[:project_uuid])
  end

  def set_event
    @event = @project.ingest_events.find_by!(uuid: params[:uuid])
  end
end
