# frozen_string_literal: true

require "json"

module Logister
  class SidekiqReadiness
    QUEUES = %w[projector notifications mailers analytics integrations symbols maintenance].freeze
    def initialize(redis:, concurrency:, now: Time.current, connection_pool: ActiveRecord::Base.connection_pool)
      @redis = redis
      @concurrency = Integer(concurrency)
      @now = now.utc
      @connection_pool = connection_pool
    end

    def call
      {
        "sidekiq_processes" => redis.scard("processes"),
        "queues" => queue_status,
        "retry_size" => redis.zcard("retry"),
        "dead_size" => redis.zcard("dead"),
        "scheduled_size" => redis.zcard("schedule"),
        "scheduler" => SidekiqRecurringScheduler.status(now, redis: redis),
        "worker_database_pools" => WorkerPoolHeartbeat.all(redis: redis),
        "redis" => redis_status,
        "database_pool" => database_pool_status
      }
    end

    private

    attr_reader :redis, :now

    def queue_status
      QUEUES.to_h do |queue|
        size = redis.llen("queue:#{queue}")
        payload = parse_job(redis.lindex("queue:#{queue}", -1))
        enqueued_at = job_enqueued_at(payload)
        [ queue, {
          "size" => size,
          "oldest_enqueued_at" => enqueued_at&.iso8601,
          "age_seconds" => enqueued_at ? [ (now - enqueued_at).to_i, 0 ].max : 0
        } ]
      end
    end

    def parse_job(payload)
      parsed = JSON.parse(payload.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError, TypeError, ArgumentError
      {}
    end

    def job_enqueued_at(payload)
      Time.at(Float(payload.fetch("enqueued_at"))).utc if payload["enqueued_at"]
    rescue TypeError, ArgumentError
      nil
    end

    def redis_status
      persistence = safe_info("persistence")
      replication = safe_info("replication")
      policy = safe_config("maxmemory-policy")
      appendonly = safe_config("appendonly")
      save = safe_config("save")
      persistent = appendonly == "yes" || save.present? || persistence["aof_enabled"] == "1"

      {
        "maxmemory_policy" => policy.presence || "unknown",
        "sidekiq_policy_valid" => policy == "noeviction",
        "persistence_configured" => persistent,
        "aof_enabled" => persistence["aof_enabled"] == "1",
        "role" => replication["role"].presence || "unknown",
        "connected_replicas" => replication["connected_slaves"].to_i,
        "high_availability_observed" => replication["role"] == "master" && replication["connected_slaves"].to_i.positive?
      }
    end

    def safe_info(section)
      redis.info(section).to_h
    rescue Redis::BaseError
      {}
    end

    def safe_config(key)
      result = redis.config(:get, key)
      result.is_a?(Hash) ? result[key].to_s : Array(result).last.to_s
    rescue Redis::BaseError
      nil
    end

    def database_pool_status
      WorkerPoolHeartbeat.status(concurrency: @concurrency, connection_pool: @connection_pool)
    end
  end
end
