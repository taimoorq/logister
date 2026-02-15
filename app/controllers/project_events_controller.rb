class ProjectEventsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_event

  def show
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
