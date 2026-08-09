# frozen_string_literal: true

class GooglePlayImportJob < ApplicationJob
  queue_as :integrations

  def perform(project_integration_setting_id, schedule_token = nil)
    setting = ProjectIntegrationSetting.find_by(id: project_integration_setting_id)
    return unless setting&.provider_google_play? && setting.configured? && !setting.project.archived?

    GooglePlay::Importer.new(setting).call
  ensure
    setting&.release_import_schedule!(token: schedule_token)
  end
end
