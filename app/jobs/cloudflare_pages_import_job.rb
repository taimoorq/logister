class CloudflarePagesImportJob < ApplicationJob
  queue_as :default

  def perform(project_integration_setting_id)
    setting = ProjectIntegrationSetting.find_by(id: project_integration_setting_id)
    Logister::CloudflarePagesImporter.call(setting)
  end
end
