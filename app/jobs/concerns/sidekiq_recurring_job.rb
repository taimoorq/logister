# frozen_string_literal: true

module SidekiqRecurringJob
  extend ActiveSupport::Concern

  included do
    class_attribute :sidekiq_recurring_key
    class_attribute :sidekiq_recurring_every
    class_attribute :sidekiq_recurring_daily_at
    class_attribute :sidekiq_recurring_schedule_ttl
    class_attribute :sidekiq_recurring_arguments
  end

  class_methods do
    def sidekiq_recurring_schedule(key:, every: nil, daily_at: nil, schedule_ttl: nil, arguments: nil)
      if every.present? == daily_at.present?
        raise ArgumentError, "Configure exactly one Sidekiq recurring schedule type"
      end

      self.sidekiq_recurring_key = key.to_s
      self.sidekiq_recurring_every = every
      self.sidekiq_recurring_daily_at = daily_at
      self.sidekiq_recurring_schedule_ttl = schedule_ttl || default_sidekiq_recurring_schedule_ttl(every:)
      self.sidekiq_recurring_arguments = arguments || ->(_run_at) { [] }
    end

    def ensure_scheduled!(now = Time.current)
      run_at = next_sidekiq_recurring_run_at(now)
      return unless sidekiq_recurring_redis_set_once(sidekiq_recurring_schedule_key(run_at), sidekiq_recurring_schedule_ttl)

      set(wait_until: run_at).perform_later(*Array(sidekiq_recurring_arguments.call(run_at)))
    rescue StandardError => e
      Rails.logger.warn("#{sidekiq_recurring_key}_schedule_failed error=#{e.class}: #{e.message}")
      report_sidekiq_recurring_schedule_failure(e, run_at)
    end

    def next_sidekiq_recurring_run_at(now)
      now = now.in_time_zone("UTC")
      return next_interval_run_at(now) if sidekiq_recurring_every.present?

      next_daily_run_at(now)
    end

    def sidekiq_recurring_redis_set_once(key, ttl)
      Sidekiq.redis { |redis| redis.set(key, "1", nx: true, ex: ttl.to_i) }
    end

    def sidekiq_recurring_schedule_key(run_at)
      "logister:sidekiq_recurring:scheduled:#{sidekiq_recurring_key}:#{run_at.utc.strftime('%Y%m%d%H%M')}"
    end

    private

    def default_sidekiq_recurring_schedule_ttl(every:)
      return 2.days.to_i if every.blank?

      every.to_i * 2
    end

    def next_interval_run_at(now)
      interval_seconds = sidekiq_recurring_every.to_i
      rounded_now = now.change(sec: 0, usec: 0)
      elapsed_seconds = rounded_now.to_i % interval_seconds
      seconds_until_next_run = elapsed_seconds.zero? && now == rounded_now ? interval_seconds : interval_seconds - elapsed_seconds

      rounded_now + seconds_until_next_run.seconds
    end

    def next_daily_run_at(now)
      hour, minute = sidekiq_recurring_daily_at.to_s.split(":", 2).map(&:to_i)
      run_at = now.change(hour: hour, min: minute, sec: 0, usec: 0)
      run_at += 1.day if run_at <= now
      run_at
    end

    def report_sidekiq_recurring_schedule_failure(error, run_at)
      Logister.report_log(
        message: "Sidekiq recurring job schedule failed",
        level: "error",
        fingerprint: "logister:sidekiq_recurring:schedule_failed:#{sidekiq_recurring_key}",
        context: {
          scheduler: {
            name: sidekiq_recurring_key,
            job_class: name,
            run_at: run_at&.utc&.iso8601,
            error: {
              class: error.class.name,
              message: error.message
            }
          }.compact
        }
      )
    rescue StandardError => report_error
      Rails.logger.warn("sidekiq recurring scheduler monitoring failed: #{report_error.class} #{report_error.message}")
    end
  end

  private

  def reschedule_sidekiq_recurring_job
    return unless Rails.env.production?

    self.class.ensure_scheduled!(Time.current)
  end
end
