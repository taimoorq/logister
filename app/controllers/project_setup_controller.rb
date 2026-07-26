class ProjectSetupController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    load_project_settings_context(include: :setup)
    @settings_section = "setup"
    @setup_active_api_key_count = @api_keys.count(&:active?)
    @setup_has_events = @project.ingest_events.exists?
    @setup_has_deployments = @project.deployments.exists?
    if @project.integration_android?
      @setup_has_mobile_token = @project.mobile_ingest_tokens.where(revoked_at: nil).where("expires_at > ?", Time.current).exists?
      @setup_has_release_metadata = @project.error_groups.joins(:error_occurrences)
                                            .where("COALESCE(error_occurrences.release, '') <> ''")
                                            .exists?
      @setup_has_mapping = @project.android_mapping_files.exists?
      @setup_has_google_play = @project.integration_settings
                                       .find_by(provider: ProjectIntegrationSetting::PROVIDERS[:google_play])
                                       &.configured? || false
      latest_android_event = @project.ingest_events.order(occurred_at: :desc).select(:id, :context, :occurred_at).first
      @setup_android_sdk = latest_android_event&.context.to_h.fetch("sdk", {})
    end

    render "projects/setup"
  end
end
