# frozen_string_literal: true

class AndroidMappingFilesController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_managed_project
  before_action :require_android_project
  before_action :set_mapping_file, only: :destroy

  def create
    mapping = @project.android_mapping_files.new(mapping_file_params.except(:upload))
    mapping.uploaded_by = current_user
    mapping.upload = mapping_file_params[:upload]

    if mapping.save
      MobileArtifactCoverageRefreshJob.perform_later(@project.id, "android")
      redirect_to settings_project_path(@project, section: "integrations", anchor: "android-mappings"), notice: "R8 mapping uploaded for build #{mapping.version_code}."
    else
      redirect_to settings_project_path(@project, section: "integrations", anchor: "android-mappings"), alert: mapping.errors.full_messages.to_sentence
    end
  end

  def destroy
    version_code = @mapping_file.version_code
    @mapping_file.destroy!
    MobileArtifactCoverageRefreshJob.perform_later(@project.id, "android")
    redirect_to artifact_return_path, notice: "R8 mapping removed for build #{version_code}."
  end

  private

  def set_mapping_file
    @mapping_file = @project.android_mapping_files.find_by!(uuid: params[:uuid])
  end

  def mapping_file_params
    params.require(:android_mapping_file).permit(:package_name, :version_name, :version_code, :release, :upload)
  end

  def require_android_project
    head :not_found unless @project.integration_android?
  end

  def artifact_return_path
    return artifacts_project_path(@project) if params[:return_to] == "artifacts"

    settings_project_path(@project, section: "integrations", anchor: "android-mappings")
  end
end
