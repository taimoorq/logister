# frozen_string_literal: true

require "time"
require "securerandom"

module SidekiqRecurringJob
  extend ActiveSupport::Concern

  included do
    class_attribute :sidekiq_recurring_key
    class_attribute :sidekiq_recurring_every
    class_attribute :sidekiq_recurring_daily_at
    class_attribute :sidekiq_recurring_schedule_ttl
    class_attribute :sidekiq_recurring_arguments
    class_attribute :sidekiq_recurring_lookahead

    around_perform :track_sidekiq_recurring_execution
  end

  class_methods do
    def sidekiq_recurring_schedule(key:, every: nil, daily_at: nil, schedule_ttl: nil, arguments: nil, lookahead: nil)
      if every.present? == daily_at.present?
        raise ArgumentError, "Configure exactly one Sidekiq recurring schedule type"
      end

      self.sidekiq_recurring_key = key.to_s
      self.sidekiq_recurring_every = every
      self.sidekiq_recurring_daily_at = daily_at
      self.sidekiq_recurring_schedule_ttl = schedule_ttl || default_sidekiq_recurring_schedule_ttl(every:)
      self.sidekiq_recurring_arguments = arguments || ->(_run_at) { [] }
      self.sidekiq_recurring_lookahead = lookahead || (every.present? ? 4 : 3)
    end

    def ensure_scheduled!(now = Time.current, occurrences: sidekiq_recurring_lookahead)
      cursor = now
      Integer(occurrences).times do
        run_at = next_sidekiq_recurring_run_at(cursor)
        cursor = run_at
        ttl = [ sidekiq_recurring_schedule_ttl.to_i, (run_at - now).ceil + sidekiq_recurring_schedule_ttl.to_i ].max
        schedule_key = sidekiq_recurring_schedule_key(run_at)
        marker_token = SecureRandom.uuid
        next unless sidekiq_recurring_redis_set_once(schedule_key, ttl, value: marker_token)

        begin
          enqueued_job = set(wait_until: run_at).perform_later(*Array(sidekiq_recurring_arguments.call(run_at)))
          raise ActiveJob::EnqueueError, "#{name} was not enqueued" unless enqueued_job
        rescue StandardError
          sidekiq_recurring_release_marker(schedule_key, marker_token)
          raise
        end
      rescue StandardError => e
        Rails.logger.warn("#{sidekiq_recurring_key}_schedule_failed error=#{e.class}: #{e.message}")
        report_sidekiq_recurring_schedule_failure(e, run_at)
        break
      end
    end

    def next_sidekiq_recurring_run_at(now)
      now = now.in_time_zone("UTC")
      return next_interval_run_at(now) if sidekiq_recurring_every.present?

      next_daily_run_at(now)
    end

    def sidekiq_recurring_redis_set_once(key, ttl, value: "1")
      Sidekiq.redis { |redis| redis.set(key, value, nx: true, ex: ttl.to_i) }
    end

    def sidekiq_recurring_release_marker(key, marker_token)
      script = <<~LUA.squish
        if redis.call('get', KEYS[1]) == ARGV[1] then
          return redis.call('del', KEYS[1])
        end
        return 0
      LUA
      Sidekiq.redis { |redis| redis.call("EVAL", script, 1, key, marker_token) }
    rescue StandardError => error
      Rails.logger.warn(
        "#{sidekiq_recurring_key}_schedule_marker_release_failed " \
        "error=#{error.class}: #{error.message}"
      )
      false
    end

    def sidekiq_recurring_schedule_key(run_at)
      "logister:sidekiq_recurring:scheduled:#{sidekiq_recurring_key}:#{run_at.utc.strftime('%Y%m%d%H%M')}"
    end

    def sidekiq_recurring_status(now = Time.current, redis: nil)
      state = sidekiq_recurring_redis(redis) { |connection| connection.hgetall(sidekiq_recurring_state_key) }
      expected_at = previous_sidekiq_recurring_run_at(now)
      last_started_at = parse_sidekiq_recurring_time(state["started_at"])
      lateness = last_started_at && last_started_at >= expected_at ? 0 : [ (now.utc - expected_at).to_i, 0 ].max

      {
        "key" => sidekiq_recurring_key,
        "job_class" => name,
        "expected_at" => expected_at.iso8601,
        "last_started_at" => last_started_at&.iso8601,
        "last_completed_at" => parse_sidekiq_recurring_time(state["completed_at"])&.iso8601,
        "last_failed_at" => parse_sidekiq_recurring_time(state["failed_at"])&.iso8601,
        "lateness_seconds" => lateness
      }
    rescue StandardError => error
      { "key" => sidekiq_recurring_key, "job_class" => name, "status" => "unknown", "error_class" => error.class.name }
    end

    def record_sidekiq_recurring_execution!(field, at: Time.current)
      sidekiq_recurring_redis do |redis|
        redis.hset(sidekiq_recurring_state_key, field.to_s, at.utc.iso8601(6))
        redis.expire(sidekiq_recurring_state_key, 14.days.to_i)
      end
    rescue StandardError => error
      Rails.logger.warn("#{sidekiq_recurring_key}_state_failed error=#{error.class}: #{error.message}")
    end

    private

    def sidekiq_recurring_redis(redis = nil)
      return yield redis if redis

      Sidekiq.redis { |connection| yield connection }
    end

    def sidekiq_recurring_state_key
      "logister:sidekiq_recurring:state:#{sidekiq_recurring_key}"
    end

    def parse_sidekiq_recurring_time(value)
      Time.iso8601(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end

    def previous_sidekiq_recurring_run_at(now)
      offset = sidekiq_recurring_every.present? ? sidekiq_recurring_every : 1.day
      next_sidekiq_recurring_run_at(now - offset)
    end

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

  def track_sidekiq_recurring_execution
    return yield unless Rails.env.production?

    self.class.record_sidekiq_recurring_execution!(:started_at)
    yield
    self.class.record_sidekiq_recurring_execution!(:completed_at)
  rescue StandardError
    self.class.record_sidekiq_recurring_execution!(:failed_at)
    raise
  end

  def reschedule_sidekiq_recurring_job
    return unless Rails.env.production?

    self.class.ensure_scheduled!(Time.current)
  end
end
