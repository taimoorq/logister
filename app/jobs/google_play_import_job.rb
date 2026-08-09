# frozen_string_literal: true

class GooglePlayImportJob < ApplicationJob
  queue_as :integrations

  def perform(project_integration_setting_id)
    setting = ProjectIntegrationSetting.find_by(id: project_integration_setting_id)
    return unless setting&.provider_google_play? && setting.configured?

    GooglePlay::Importer.new(setting).call
  end
end
