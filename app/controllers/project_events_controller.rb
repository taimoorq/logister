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

    if turbo_frame_request?
      render partial: "project_events/event_detail", locals: {
        project:     @project,
        event:       @event,
        group:       @group,
        occurrences: @occurrences
      }
    else
      redirect_to project_path(@project, group_uuid: @group&.uuid, filter: params[:filter], q: params[:q])
    end
  end

  private

  def set_project
    project_identifier = params[:project_uuid] || params[:project_id]
    @project = current_user.accessible_projects.find_by!(uuid: project_identifier)
  end

  def set_event
    event_identifier = params[:uuid] || params[:id]
    @event = @project.ingest_events.find_by!(uuid: event_identifier)
  end
end
