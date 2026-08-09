# frozen_string_literal: true

class Api::V1::Cli::ArtifactsController < Api::V1::Cli::BaseController
  before_action -> { require_cli_scopes!("artifacts:write") }
  before_action :require_cli_project_manager!

  def android_mapping
    return render_platform_not_found unless cli_project.integration_android?

    mapping = cli_project.android_mapping_files.new(android_mapping_params.except(:file))
    mapping.uploaded_by = current_cli_access_token.user
    mapping.upload = android_mapping_params[:file]
    mapping.save!
    MobileArtifactCoverageRefreshJob.perform_later(cli_project.id, "android")

    render json: {
      artifact: "android_mapping",
      uuid: mapping.uuid,
      package_name: mapping.package_name,
      version_name: mapping.version_name,
      version_code: mapping.version_code,
      release: mapping.release,
      checksum_sha256: mapping.checksum_sha256,
      byte_size: mapping.byte_size,
      status: "available",
      coverage_refresh: "queued"
    }.compact, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_invalid_artifact(error.record.errors.full_messages)
  end

  def apple_dsym
    return render_platform_not_found unless cli_project.integration_ios?

    artifact = AppleSymbols::ArtifactUploader.new(
      project: cli_project,
      uploaded_by: current_cli_access_token.user,
      attributes: apple_dsym_params.except(:file),
      upload: apple_dsym_params[:file]
    ).call

    render json: {
      artifact: "apple_dsym",
      uuid: artifact.uuid,
      app_identifier: artifact.app_identifier,
      version_name: artifact.version_name,
      version_code: artifact.version_code,
      release: artifact.release,
      binary_uuid: artifact.binary_uuid,
      architecture: artifact.architecture,
      checksum_sha256: artifact.checksum_sha256,
      byte_size: artifact.byte_size,
      status: artifact.status,
      verification: "queued",
      coverage_refresh: "queued"
    }.compact, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_invalid_artifact(error.record.errors.full_messages)
  rescue AppleSymbols::ArtifactUploader::Error => error
    render_invalid_artifact([ error.message ])
  end

  private

  def android_mapping_params
    params.permit(:package_name, :version_name, :version_code, :release, :file)
  end

  def apple_dsym_params
    params.permit(:app_identifier, :version_name, :version_code, :release, :binary_uuid, :architecture, :file)
  end

  def render_platform_not_found
    render json: {
      error: "Not found",
      code: "unsupported_project_type",
      message: "This artifact type does not match the project's integration type."
    }, status: :not_found
  end

  def render_invalid_artifact(messages)
    render json: {
      error: "Invalid artifact",
      code: "invalid_artifact",
      message: Array(messages).to_sentence
    }, status: :unprocessable_content
  end
end
