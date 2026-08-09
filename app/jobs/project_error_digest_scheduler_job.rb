# frozen_string_literal: true

require "time"
require "securerandom"

class ProjectErrorDigestSchedulerJob < ApplicationJob
  queue_as :notifications

  LOCK_TTL = 55.minutes.to_i
  SCHEDULE_TTL = 2.hours.to_i
  CHECK_IN_SLUG = "logister.error_digest_scheduler"
  CHECK_IN_INTERVAL_SECONDS = 65.minutes.to_i
  SCHEDULE_LOOKAHEAD = 4
  STATE_TTL = 14.days.to_i

  def self.ensure_scheduled!(now = Time.current, occurrences: SCHEDULE_LOOKAHEAD)
    cursor = now
    Integer(occurrences).times do
      run_at = next_run_at(cursor)
      cursor = run_at
      key = schedule_key(run_at)
      ttl = SCHEDULE_TTL + (run_at - now).ceil
      marker_token = SecureRandom.uuid
      next unless redis_set_once(key, ttl, value: marker_token)

      begin
        enqueued_job = set(wait_until: run_at).perform_later
        raise ActiveJob::EnqueueError, "#{name} was not enqueued" unless enqueued_job
      rescue StandardError
        release_schedule_marker(key, marker_token)
        raise
      end
    rescue StandardError => e
      Rails.logger.warn("error_digest_scheduler_schedule_failed error=#{e.class}: #{e.message}")
      report_schedule_failure(e, run_at)
      break
    end
  end

  def self.next_run_at(now)
    now = now.in_time_zone("UTC")
    now.beginning_of_hour + 1.hour + 2.minutes
  end

  def self.redis_set_once(key, ttl, value: "1")
    Sidekiq.redis { |redis| redis.set(key, value, nx: true, ex: ttl) }
  end

  def self.release_schedule_marker(key, marker_token)
    script = <<~LUA.squish
      if redis.call('get', KEYS[1]) == ARGV[1] then
        return redis.call('del', KEYS[1])
      end
      return 0
    LUA
    Sidekiq.redis { |redis| redis.call("EVAL", script, 1, key, marker_token) }
  rescue StandardError => error
    Rails.logger.warn(
      "error_digest_scheduler_schedule_marker_release_failed " \
      "error=#{error.class}: #{error.message}"
    )
    false
  end

  def self.schedule_key(run_at)
    "logister:error_digest_scheduler:scheduled:#{run_at.utc.strftime('%Y%m%d%H')}"
  end

  def self.recurring_status(now = Time.current, redis: nil)
    state = with_redis(redis) { |connection| connection.hgetall(state_key) }
    expected_at = next_run_at(now - 1.hour)
    last_started_at = parse_state_time(state["started_at"])
    {
      "key" => CHECK_IN_SLUG,
      "job_class" => name,
      "expected_at" => expected_at.iso8601,
      "last_started_at" => last_started_at&.iso8601,
      "last_completed_at" => parse_state_time(state["completed_at"])&.iso8601,
      "last_failed_at" => parse_state_time(state["failed_at"])&.iso8601,
      "lateness_seconds" => last_started_at && last_started_at >= expected_at ? 0 : [ (now.utc - expected_at).to_i, 0 ].max
    }
  rescue StandardError => error
    { "key" => CHECK_IN_SLUG, "job_class" => name, "status" => "unknown", "error_class" => error.class.name }
  end

  def self.record_execution!(field, at: Time.current)
    with_redis do |redis|
      redis.hset(state_key, field.to_s, at.utc.iso8601(6))
      redis.expire(state_key, STATE_TTL)
    end
  rescue StandardError => error
    Rails.logger.warn("error_digest_scheduler_state_failed error=#{error.class}: #{error.message}")
  end

  def self.with_redis(redis = nil)
    return yield redis if redis

    Sidekiq.redis { |connection| yield connection }
  end
  private_class_method :with_redis

  def self.state_key
    "logister:sidekiq_recurring:state:#{CHECK_IN_SLUG}"
  end
  private_class_method :state_key

  def self.parse_state_time(value)
    Time.iso8601(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end
  private_class_method :parse_state_time

  def self.report_schedule_failure(error, run_at)
    Logister.report_log(
      message: "Error digest scheduler enqueue failed",
      level: "error",
      fingerprint: "logister:error_digest_scheduler:schedule_failed",
      context: {
        scheduler: {
          name: CHECK_IN_SLUG,
          run_at: run_at&.utc&.iso8601,
          error: {
            class: error.class.name,
            message: error.message
          }
        }.compact
      }
    )
  rescue StandardError => report_error
    Rails.logger.warn("error digest scheduler monitoring failed: #{report_error.class} #{report_error.message}")
  end
  private_class_method :report_schedule_failure

  def perform(now_iso8601 = Time.current.iso8601)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    now = nil
    self.class.record_execution!(:started_at) if Rails.env.production?
    now = Time.zone.parse(now_iso8601.to_s)
    unless self.class.redis_set_once(lock_key(now), LOCK_TTL)
      self.class.record_execution!(:completed_at) if Rails.env.production?
      return
    end

    queued_digests = enqueue_due_digests(now)
    report_scheduler_check_in(status: "ok", now: now, queued_digests: queued_digests, started_at: started_at)
    self.class.record_execution!(:completed_at) if Rails.env.production?
  rescue StandardError => e
    self.class.record_execution!(:failed_at) if Rails.env.production?
    report_scheduler_failure(e, now: now, started_at: started_at)
    raise
  ensure
    self.class.ensure_scheduled!(Time.current)
  end

  private

  def enqueue_due_digests(now)
    queued_digests = 0

    ProjectNotificationPreference.digest_enabled.for_active_projects.find_each do |preference|
      window = preference.due_digest_window(now)
      next unless window

      period_start, period_end = window
      next if digest_delivery_exists?(preference, period_start)

      ProjectErrorDigestJob.perform_later(
        preference.id,
        period_start.utc.iso8601,
        period_end.utc.iso8601,
        preference.digest_frequency
      )
      queued_digests += 1
    end

    queued_digests
  end

  def digest_delivery_exists?(preference, period_start)
    EmailNotificationDelivery.exists?(
      dedup_key: EmailNotificationDelivery.digest_key(
        preference: preference,
        period_start: period_start,
        frequency: preference.digest_frequency
      )
    )
  end

  def lock_key(now)
    "logister:error_digest_scheduler:lock:#{now.utc.strftime('%Y%m%d%H')}"
  end

  def report_scheduler_check_in(status:, now:, queued_digests:, started_at:)
    Logister.report_check_in(
      slug: CHECK_IN_SLUG,
      status: status,
      expected_interval_seconds: CHECK_IN_INTERVAL_SECONDS,
      duration_ms: elapsed_ms(started_at),
      context: {
        scheduler: {
          name: CHECK_IN_SLUG,
          ran_at: now&.utc&.iso8601,
          queued_digests: queued_digests
        }.compact
      }
    )
  rescue StandardError => report_error
    Rails.logger.warn("error digest scheduler check-in failed: #{report_error.class} #{report_error.message}")
  end

  def report_scheduler_failure(error, now:, started_at:)
    report_scheduler_check_in(status: "error", now: now, queued_digests: 0, started_at: started_at)
    Logister.report_log(
      message: "Error digest scheduler failed",
      level: "error",
      fingerprint: "logister:error_digest_scheduler:failure",
      context: {
        scheduler: {
          name: CHECK_IN_SLUG,
          ran_at: now&.utc&.iso8601,
          error: {
            class: error.class.name,
            message: error.message
          }
        }.compact
      }
    )
  rescue StandardError => report_error
    Rails.logger.warn("error digest scheduler failure monitoring failed: #{report_error.class} #{report_error.message}")
  end

  def elapsed_ms(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)
  end
end
