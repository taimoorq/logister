class ProjectIntegrationSettingsController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_managed_project

  def update
    @integration_setting = ProjectIntegrationSetting.for(
      project: @project,
      provider: integration_setting_params.fetch(:provider)
    )
    @integration_setting.assign_attributes(integration_setting_params)

    if @integration_setting.save
      redirect_to settings_project_path(@project, section: "integrations", anchor: integration_anchor),
                  notice: "#{@integration_setting.provider.humanize} settings updated."
    else
      @cloudflare_integration_setting = @integration_setting if @integration_setting.provider_cloudflare_pages?
      @google_play_integration_setting = @integration_setting if @integration_setting.provider_google_play?
      @app_store_connect_integration_setting = @integration_setting if @integration_setting.provider_app_store_connect?
      @settings_section = "integrations"
      load_project_settings_context
      render "projects/settings", status: :unprocessable_content
    end
  end

  def import
    setting = @project.integration_settings.find_by!(provider: ProjectIntegrationSetting::PROVIDERS[:google_play])
    if setting.configured?
      GooglePlayImportJob.perform_later(setting.id)
      redirect_to settings_project_path(@project, section: "integrations", anchor: "google-play-integration"), notice: "Google Play import queued."
    else
      redirect_to settings_project_path(@project, section: "integrations", anchor: "google-play-integration"), alert: "Configure the package and credential reference before importing."
    end
  end

  private

  def integration_anchor
    if @integration_setting.provider_google_play?
      "google-play-integration"
    elsif @integration_setting.provider_app_store_connect?
      "app-store-connect-integration"
    else
      "platform-integration"
    end
  end

  def integration_setting_params
    params.require(:project_integration_setting).permit(
      :provider,
      :enabled,
      :account_id,
      :external_project_id,
      :external_project_name,
      :credential_reference,
      metadata: { track_allowlist: [] }
    ).tap do |permitted|
      permitted[:enabled] = ActiveModel::Type::Boolean.new.cast(permitted[:enabled]) if permitted.key?(:enabled)
    end
  end
end
