class ProjectIntegrationSettingsController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_managed_project
  before_action :reject_archived_project

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
    provider = params[:provider].to_s.presence_in(%w[google_play app_store_connect]) || "google_play"
    setting = @project.integration_settings.find_by!(provider: provider)
    anchor = provider == "app_store_connect" ? "app-store-connect-integration" : "google-play-integration"
    label = provider == "app_store_connect" ? "App Store Connect" : "Google Play"

    unless setting.configured?
      redirect_to settings_project_path(@project, section: "integrations", anchor: anchor), alert: "Configure #{label} credentials before importing."
      return
    end

    if provider == "app_store_connect"
      AppStoreConnectImportJob.perform_later(setting.id)
    else
      GooglePlayImportJob.perform_later(setting.id)
    end
    redirect_to settings_project_path(@project, section: "integrations", anchor: anchor), notice: "#{label} import queued."
  end

  private

  def reject_archived_project
    return unless @project.archived?

    redirect_to settings_project_path(@project, section: "integrations"),
                alert: "Distribution and platform imports are paused while this project is archived. Restore the project before changing or syncing an integration."
  end

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
