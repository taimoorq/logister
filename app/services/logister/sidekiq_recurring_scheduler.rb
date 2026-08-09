# frozen_string_literal: true

module Logister
  class SidekiqRecurringScheduler
    RECONCILE_KEY = "logister:sidekiq_recurring:reconcile"
    RECONCILE_INTERVAL = 1.minute
    JOBS = [
      TelemetryProjectorJob,
      ProjectErrorDigestSchedulerJob,
      ProjectRetentionSweepJob,
      ProjectMonitorSweepJob,
      ProjectHealthNotificationSweepJob,
      ProjectEmailNotificationRecoverySweepJob,
      NotificationIntentSweepJob,
      NotificationEvaluationSweepJob,
      ProjectPurgeRecoverySweepJob,
      AppStoreConnectImportSweepJob,
      IngestEventsPartitionMaintenanceJob,
      ClickhouseCoverageSealerJob,
      TelemetryLedgerCleanupJob
    ].freeze

    def self.install!(now = Time.current)
      JOBS.each { |job_class| job_class.ensure_scheduled!(now) }
    end

    def self.reconcile!(now = Time.current)
      acquired = Sidekiq.redis do |redis|
        redis.set(RECONCILE_KEY, now.utc.iso8601(6), nx: true, ex: RECONCILE_INTERVAL.to_i)
      end
      install!(now) if acquired
    rescue StandardError => error
      Rails.logger.warn("Sidekiq recurring reconciliation failed: #{error.class} #{error.message}")
    end

    def self.status(now = Time.current, redis: nil)
      JOBS.filter_map do |job_class|
        if job_class.respond_to?(:sidekiq_recurring_status)
          job_class.sidekiq_recurring_status(now, redis: redis)
        elsif job_class.respond_to?(:recurring_status)
          job_class.recurring_status(now, redis: redis)
        end
      end
    end
  end
end
