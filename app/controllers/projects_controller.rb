class ProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project, only: :show

  def index
    @projects = current_user.projects.order(created_at: :desc)
  end

  def show
    @api_keys = @project.api_keys.order(created_at: :desc)
    @events = @project.ingest_events.order(occurred_at: :desc).limit(50)
  end

  def new
    @project = current_user.projects.new
  end

  def create
    @project = current_user.projects.new(project_params)

    if @project.save
      redirect_to project_path(@project), notice: "Project created. Add an API key to start ingesting events."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @project = current_user.projects.find_by!(uuid: params[:uuid])
  end

  def project_params
    params.require(:project).permit(:name, :slug, :description)
  end
end
