class ProjectLinksController < ApplicationController
  include ProjectScope
  before_action :authenticate_user!
  before_action :set_managed_project

  def index
    @connection = build_connection
    @connection.peer # Reject inaccessible or stale project choices before rendering.
    load_links
  end

  def create
    @connection = build_connection
    if @connection.save
      redirect_to project_project_links_path(@project, direction: @connection.direction), status: :see_other,
        notice: "#{@connection.source.name} is now linked to #{@connection.target.name}."
    else
      load_links
      render :index, status: :unprocessable_content
    end
  end

  def update
    @project.update!(cross_project_correlations_enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    redirect_to project_project_links_path(@project), notice: "Related request setting updated."
  end

  def destroy
    ProjectLink.touching(@project).find_by!(uuid: params[:uuid]).disconnect!(actor: current_user)
    redirect_to project_project_links_path(@project), notice: "Project disconnected."
  end

  private

  def build_connection
    attributes = params.permit(:direction, :peer_project_uuid, :source_environment, :target_environment,
      :custom_source_environment, :custom_target_environment).to_h.symbolize_keys
    # Honor forms opened before the new app/backend picker was deployed.
    if params[:target_project_uuid].present? && attributes[:peer_project_uuid].blank?
      attributes.merge!(direction: "outgoing", peer_project_uuid: params[:target_project_uuid])
    end
    ProjectConnectionForm.new(project: @project, actor: current_user, **attributes)
  end

  def load_links
    @project_options = @connection.project_options
    if @connection.peer
      @source_environment_groups = @connection.environment_groups(@connection.source)
      @target_environment_groups = @connection.environment_groups(@connection.target)
    end
    visible = current_user.accessible_projects.select(:id)
    @links = ProjectLink.touching(@project).where(source_project_id: visible, target_project_id: visible)
      .includes(:source_project, :target_project).order(:created_at)
  end
end
