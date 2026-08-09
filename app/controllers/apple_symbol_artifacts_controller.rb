# frozen_string_literal: true

class AppleSymbolArtifactsController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_managed_project
  before_action :require_ios_project
  before_action :set_artifact, only: %i[destroy process_artifact]

  def create
    artifact = AppleSymbols::ArtifactUploader.new(
      project: @project,
      uploaded_by: current_user,
      attributes: artifact_params.except(:upload),
      upload: artifact_params[:upload]
    ).call
    redirect_to settings_project_path(@project, section: "integrations", anchor: "apple-symbols"),
                notice: "dSYM archive uploaded for build #{artifact.version_code}; UUID verification was queued."
  rescue ActiveRecord::RecordInvalid, AppleSymbols::ArtifactUploader::Error => error
    redirect_to settings_project_path(@project, section: "integrations", anchor: "apple-symbols"), alert: error.message
  end

  def process_artifact
    AppleSymbolArtifactProcessingJob.perform_later(@artifact.id)
    redirect_to artifact_return_path, notice: "dSYM verification queued."
  end

  def destroy
    build = @artifact.version_code
    @artifact.destroy!
    MobileArtifactCoverageRefreshJob.perform_later(@project.id, "ios")
    redirect_to artifact_return_path, notice: "dSYM archive removed for build #{build}."
  end

  private

  def set_artifact
    @artifact = @project.apple_symbol_artifacts.find_by!(uuid: params[:uuid])
  end

  def artifact_params
    params.require(:apple_symbol_artifact).permit(:app_identifier, :version_name, :version_code, :release, :binary_uuid, :architecture, :upload)
  end

  def require_ios_project
    head :not_found unless @project.integration_ios?
  end

  def artifact_return_path
    return artifacts_project_path(@project) if params[:return_to] == "artifacts"

    settings_project_path(@project, section: "integrations", anchor: "apple-symbols")
  end
end
