# frozen_string_literal: true

class AppStoreConnectImportJob < ApplicationJob
  queue_as :integrations

  def perform(project_integration_setting_id)
    setting = ProjectIntegrationSetting.find_by(id: project_integration_setting_id)
    return unless setting&.provider_app_store_connect? && setting.configured?

    AppStoreConnect::Importer.new(setting).call
  end
end
