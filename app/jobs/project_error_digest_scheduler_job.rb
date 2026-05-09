class ProjectErrorDigestSchedulerJob < ApplicationJob
  queue_as :notifications

  LOCK_TTL = 55.minutes.to_i
  SCHEDULE_TTL = 2.hours.to_i

  def self.ensure_scheduled!(now = Time.current)
    run_at = next_run_at(now)
    key = schedule_key(run_at)
    return unless redis_set_once(key, SCHEDULE_TTL)

    set(wait_until: run_at).perform_later
  rescue StandardError => e
    Rails.logger.warn("error_digest_scheduler_schedule_failed error=#{e.class}: #{e.message}")
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

  def perform(now_iso8601 = Time.current.iso8601)
    now = Time.zone.parse(now_iso8601.to_s)
    return unless self.class.redis_set_once(lock_key(now), LOCK_TTL)

    enqueue_due_digests(now)
  ensure
    self.class.ensure_scheduled!(Time.current)
  end

  private

  def enqueue_due_digests(now)
    ProjectNotificationPreference.digest_enabled.find_each do |preference|
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
    end
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
end
