# frozen_string_literal: true

module Logister
  class SidekiqRecurringScheduler
    JOBS = [
      ProjectErrorDigestSchedulerJob,
      ProjectRetentionSweepJob,
      ProjectMonitorSweepJob,
      ProjectHealthNotificationSweepJob
    ].freeze

    def self.install!(now = Time.current)
      JOBS.each { |job_class| job_class.ensure_scheduled!(now) }
    end
  end
end
