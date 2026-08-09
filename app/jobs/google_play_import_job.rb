# frozen_string_literal: true

class GooglePlayImportJob < ApplicationJob
  queue_as :integrations

  MAX_ATTEMPTS = 5
  MAX_RETRY_DELAY = 15.minutes

  def perform(project_integration_setting_id, schedule_token = nil)
    retry_scheduled = false
    setting = ProjectIntegrationSetting.find_by(id: project_integration_setting_id)
    return unless setting&.provider_google_play? && setting.configured? && !setting.project.archived?

    GooglePlay::Importer.new(setting).call
  rescue GooglePlay::DeveloperReportingClient::Error => error
    raise unless error.retryable? && executions < MAX_ATTEMPTS

    delay = retry_delay(error)
    setting&.renew_import_schedule!(token: schedule_token, lease_for: delay + 5.minutes)
    retry_scheduled = true
    retry_job(wait: delay, error: error)
  ensure
    setting&.release_import_schedule!(token: schedule_token) unless retry_scheduled
  end

  private

  def retry_delay(error)
    requested = error.retry_after || 30.seconds * (2**[ executions - 1, 0 ].max)
    [ requested, MAX_RETRY_DELAY ].min
  end
end
