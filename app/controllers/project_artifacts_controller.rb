# frozen_string_literal: true

class ProjectArtifactsController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_accessible_project
  before_action :require_mobile_project!

  def index
    @artifact_page = [ params[:page].to_i, 1 ].max
    @artifact_index = ProjectMobileArtifactIndex.new(@project, page: @artifact_page).call
    @can_manage_artifacts = @project.managed_by?(current_user)
    @project_manager = @can_manage_artifacts
    load_artifact_upload_context if @can_manage_artifacts

    render "projects/artifacts"
  end

  private

  def require_mobile_project!
    return if @project.integration_android? || @project.integration_ios?

    raise ActiveRecord::RecordNotFound
  end
end
