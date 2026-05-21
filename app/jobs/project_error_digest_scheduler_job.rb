class ProjectErrorDigestSchedulerJob < ApplicationJob
  queue_as :notifications

  LOCK_TTL = 55.minutes.to_i
  SCHEDULE_TTL = 2.hours.to_i
  CHECK_IN_SLUG = "logister.error_digest_scheduler"
  CHECK_IN_INTERVAL_SECONDS = 65.minutes.to_i

  def self.ensure_scheduled!(now = Time.current)
    run_at = next_run_at(now)
    key = schedule_key(run_at)
    return unless redis_set_once(key, SCHEDULE_TTL)

    set(wait_until: run_at).perform_later
  rescue StandardError => e
    Rails.logger.warn("error_digest_scheduler_schedule_failed error=#{e.class}: #{e.message}")
    report_schedule_failure(e, run_at)
  end

  def self.next_run_at(now)
    now = now.in_time_zone("UTC")
    now.beginning_of_hour + 1.hour + 2.minutes
  end

  def self.redis_set_once(key, ttl)
    Sidekiq.redis { |redis| redis.set(key, "1", nx: true, ex: ttl) }
  end

  def self.schedule_key(run_at)
    "logister:error_digest_scheduler:scheduled:#{run_at.utc.strftime('%Y%m%d%H')}"
  end

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
    now = Time.zone.parse(now_iso8601.to_s)
    return unless self.class.redis_set_once(lock_key(now), LOCK_TTL)

    queued_digests = enqueue_due_digests(now)
    report_scheduler_check_in(status: "ok", now: now, queued_digests: queued_digests, started_at: started_at)
  rescue StandardError => e
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
