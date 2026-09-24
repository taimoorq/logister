class ProjectLinksController < ApplicationController
  include ProjectScope
  before_action :authenticate_user!
  before_action :set_managed_project

  def index
    @candidates = current_user.manageable_projects.active.where(purge_requested_at: nil).where.not(id: @project.id).order(:name)
    visible = current_user.accessible_projects.select(:id)
    @links = ProjectLink.touching(@project).where(source_project_id: visible, target_project_id: visible).includes(:source_project, :target_project)
  end

  def create
    target = current_user.manageable_projects.find_by!(uuid: params[:target_project_uuid])
    ProjectLink.connect!(actor: current_user, source: @project, target:,
      environment_pairs: [ { "source" => params[:source_environment], "target" => params[:target_environment] } ])
    redirect_to project_project_links_path(@project), notice: "Projects connected. Enable related requests on both projects to start looking up requests."
  rescue ActiveRecord::RecordInvalid => error
    index
    flash.now[:alert] = error.record.errors.full_messages.to_sentence
    render :index, status: :unprocessable_content
  end

  def update
    @project.update!(cross_project_correlations_enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    redirect_to project_project_links_path(@project), notice: "Related request setting updated."
  end

  def destroy
    ProjectLink.touching(@project).find_by!(uuid: params[:uuid]).disconnect!(actor: current_user)
    redirect_to project_project_links_path(@project), notice: "Project disconnected."
  end
end
