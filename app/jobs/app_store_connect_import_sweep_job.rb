# frozen_string_literal: true

class AppStoreConnectImportSweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :integrations
  sidekiq_recurring_schedule(
    key: "app_store_connect_import_sweep",
    every: 15.minutes,
    arguments: ->(run_at) { [ run_at.utc.iso8601 ] }
  )

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)

    ProjectIntegrationSetting
      .joins(:project)
      .merge(Project.active)
      .where(provider: ProjectIntegrationSetting::PROVIDERS.fetch(:app_store_connect))
      .due_for_import(before: now - 15.minutes)
      .find_each do |setting|
        next unless setting.configured?

        token = setting.claim_import_schedule!(now: now)
        next unless token

        AppStoreConnectImportJob.perform_later(setting.id, token)
      rescue StandardError
        setting.release_import_schedule!(token: token) if token
        raise
      end
  ensure
    reschedule_sidekiq_recurring_job
  end
end
