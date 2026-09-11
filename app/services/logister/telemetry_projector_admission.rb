# frozen_string_literal: true

module Logister
  # Redis carries bounded wake hints. PostgreSQL remains the work ledger and
  # delivery lease authority; the periodic recovery sweep may always wake it.
  class TelemetryProjectorAdmission
    PREFIX = "logister:{telemetry_projector}:admission:v1"
    KEYS = %w[generation queued running cooldown].map { |name| "#{PREFIX}:#{name}" }.freeze
    RECOVERY_KEY = "#{PREFIX}:recovery"
    MAX_RUNNING = 3
    OWNER_SECONDS = 90
    RECOVERY_SECONDS = 60
    RESERVATION_GRACE = 30
    QUEUE_SCAN_LIMIT = 1_000

    SCRIPT = <<~LUA.freeze
      local time = redis.call('TIME')
      local now = tonumber(time[1]) + tonumber(time[2]) / 1000000
      local action = ARGV[1]
      local job = ARGV[2]
      local owner = ARGV[3]
      local capacity = tonumber(ARGV[4])
      local lease = tonumber(ARGV[5])
      redis.call('ZREMRANGEBYSCORE', KEYS[3], '-inf', now)

      local function reserve()
        if redis.call('EXISTS', KEYS[4]) == 1 then return 0 end
        if redis.call('EXISTS', KEYS[2]) == 1 or redis.call('ZCARD', KEYS[3]) >= capacity then return 0 end
        redis.call('HSET', KEYS[2], 'job_id', job, 'reserved_at', now)
        return 1
      end
      if action == 'wake' then
        redis.call('INCR', KEYS[1])
        return reserve()
      elseif action == 'enter' then
        if redis.call('HGET', KEYS[2], 'job_id') == job then redis.call('DEL', KEYS[2]) end
        if redis.call('EXISTS', KEYS[4]) == 1 then return {0, 0} end
        if redis.call('ZCARD', KEYS[3]) >= capacity then return {0, 0} end
        redis.call('ZADD', KEYS[3], now + lease, owner)
        redis.call('EXPIRE', KEYS[3], lease * 2)
        return {1, tonumber(redis.call('GET', KEYS[1]) or '0')}
      elseif action == 'renew' then
        if not redis.call('ZSCORE', KEYS[3], owner) then return 0 end
        redis.call('ZADD', KEYS[3], now + lease, owner)
        redis.call('EXPIRE', KEYS[3], lease * 2)
        return 1
      elseif action == 'finish' then
        if redis.call('ZREM', KEYS[3], owner) == 0 then return 0 end
        if ARGV[7] == '1' then redis.call('INCR', KEYS[1]) end
        if tonumber(redis.call('GET', KEYS[1]) or '0') > tonumber(ARGV[6]) then return reserve() end
        return 0
      elseif action == 'failed' then
        if redis.call('ZREM', KEYS[3], owner) == 0 then return 0 end
        redis.call('SET', KEYS[4], '1', 'EX', 10)
        return 0
      elseif action == 'reserved' then
        return redis.call('HGET', KEYS[2], 'job_id') == job and 1 or 0
      elseif action == 'clear' then
        if redis.call('HGET', KEYS[2], 'job_id') == job then return redis.call('DEL', KEYS[2]) end
        return 0
      elseif action == 'orphan_candidate' then
        local reserved = tonumber(redis.call('HGET', KEYS[2], 'reserved_at') or now)
        if now - reserved >= tonumber(ARGV[6]) then return redis.call('HGET', KEYS[2], 'job_id') end
        return false
      end
    LUA

    class Session
      def initialize(admission, owner, generation)
        @admission, @owner, @generation = admission, owner, generation
        @checked_at = monotonic
        @lost = false
      end

      def heartbeat(force: false)
        return false if @lost || @finished
        return true if !force && monotonic - @checked_at < 5

        @lost = !@admission.renew(@owner)
        @checked_at = monotonic
        !@lost
      end

      def finish(work_left:, failed: false)
        return if @finished

        @finished = true
        @admission.finish(@owner, @generation, work_left: work_left, failed: failed)
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    def self.enabled?
      ENV["LOGISTER_BOUNDED_PROJECTOR"] == "true"
    end

    def wake
      job = TelemetryProjectorJob.new
      return false unless command("wake", job: job.job_id) == 1

      publish(job)
    rescue StandardError => error
      warn_failure(error)
      false
    end

    def enter(job_id)
      owner = SecureRandom.uuid # Unique per attempt, even when Sidekiq retries a job ID.
      admitted, generation = command("enter", job: job_id, owner: owner)
      Session.new(self, owner, generation) if admitted == 1
    rescue StandardError => error
      warn_failure(error)
      nil
    end

    def renew(owner)
      command("renew", owner: owner) == 1
    rescue StandardError => error
      warn_failure(error)
      false
    end

    def finish(owner, generation, work_left:, failed: false)
      job = TelemetryProjectorJob.new
      reserved = command(failed ? "failed" : "finish", job: job.job_id, owner: owner, generation: generation, work_left: work_left)
      publish(job) if reserved == 1
    rescue StandardError => error
      warn_failure(error)
      false
    end

    def recover
      acquired = Sidekiq.redis { |redis| redis.set(RECOVERY_KEY, "1", nx: true, ex: RECOVERY_SECONDS) }
      return false unless acquired

      candidate = command("orphan_candidate", generation: RESERVATION_GRACE)
      command("clear", job: candidate) if candidate && carrier_absent?(candidate)
      wake
    rescue StandardError => error
      warn_failure(error)
      false
    end

    private

    def command(action, job: "", owner: "", generation: 0, work_left: false)
      Sidekiq.redis do |redis|
        redis.call("EVAL", SCRIPT, KEYS.length, *KEYS, action, job, owner,
          MAX_RUNNING, OWNER_SECONDS, generation, work_left ? "1" : "0")
      end
    end

    def publish(job)
      return false unless command("reserved", job: job.job_id) == 1

      raise ActiveJob::EnqueueError, "Projector wake was not enqueued" unless job.enqueue

      true
    rescue StandardError
      command("clear", job: job.job_id)
      raise
    end

    def carrier_absent?(job_id)
      # A marker has no TTL: a worker outage must not create more queued hints.
      # Reclaim only a proven orphan. Large/malformed queues remain conservative.
      entries = Sidekiq.redis { |redis| redis.lrange("queue:#{TelemetryProjectorJob.queue_name}", 0, QUEUE_SCAN_LIMIT) }
      return false if entries.length > QUEUE_SCAN_LIMIT

      entries.none? do |entry|
        payload = JSON.parse(entry)
        arguments = payload.fetch("args")
        return false unless arguments.is_a?(Array)

        arguments.first.is_a?(Hash) && arguments.first["job_id"] == job_id
      end
    rescue JSON::ParserError, KeyError, TypeError
      false
    end

    def warn_failure(error)
      self.class.warn_failure(error)
    end

    def self.warn_failure(error)
      @warning_lock ||= Mutex.new
      @warning_lock.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if @warned_at && now - @warned_at < 60

        @warned_at = now
        SelfReportingGuard.suppress { Rails.logger.warn("telemetry_projector_admission_error error=#{error.class}") }
      end
    rescue StandardError
      false
    end
  end
end
