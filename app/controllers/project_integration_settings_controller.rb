class ProjectIntegrationSettingsController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_owned_project

  def update
    @integration_setting = ProjectIntegrationSetting.for(
      project: @project,
      provider: integration_setting_params.fetch(:provider)
    )
    @integration_setting.assign_attributes(integration_setting_params)

    if @integration_setting.save
      redirect_to settings_project_path(@project, section: "integrations", anchor: "platform-integration"),
                  notice: "#{@integration_setting.provider.humanize} settings updated."
    else
      @cloudflare_integration_setting = @integration_setting if @integration_setting.provider_cloudflare_pages?
      @settings_section = "integrations"
      load_project_settings_context
      render "projects/settings", status: :unprocessable_content
    end
  end

  private

  def integration_setting_params
    params.require(:project_integration_setting).permit(
      :provider,
      :enabled,
      :account_id,
      :external_project_id,
      :external_project_name,
      :credential_reference
    ).tap do |permitted|
      permitted[:enabled] = ActiveModel::Type::Boolean.new.cast(permitted[:enabled]) if permitted.key?(:enabled)
    end
  end
end
