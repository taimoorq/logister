# frozen_string_literal: true

class AppStoreConnectImportSweepJob < ApplicationJob
  include SidekiqRecurringJob

  queue_as :default
  sidekiq_recurring_schedule(
    key: "app_store_connect_import_sweep",
    every: 15.minutes,
    arguments: ->(run_at) { [ run_at.utc.iso8601 ] }
  )

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)

    ProjectIntegrationSetting
      .where(provider: ProjectIntegrationSetting::PROVIDERS.fetch(:app_store_connect))
      .due_for_import(before: now - 15.minutes)
      .find_each do |setting|
        AppStoreConnectImportJob.perform_later(setting.id) if setting.configured?
      end
  ensure
    reschedule_sidekiq_recurring_job
  end
end
