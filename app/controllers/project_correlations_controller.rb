class ProjectCorrelationsController < ApplicationController
  include ProjectScope
  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    @event = @project.ingest_events.find_by!(uuid: params[:uuid])
    @result = ProjectCorrelationsQuery.call(principal: current_user, project: @project, event: @event, from: params[:from], to: params[:to])
  rescue ProjectCorrelationsQuery::InvalidRange, ProjectCorrelationPolicy::TooManyProjects => error
    @error = error.message
    render :show, status: :unprocessable_content
  rescue ActiveRecord::QueryCanceled
    @error = "This lookup took too long. Choose a shorter time range and try again."
    render :show, status: :service_unavailable
  end
end
