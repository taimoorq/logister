# frozen_string_literal: true

require "socket"

module Logister
  class WorkerPoolHeartbeat
    KEY_PREFIX = "logister:worker_database_pool"
    TTL = 30
    DEFAULT_HEADROOM = 2

    class << self
      def record!(concurrency:, connection_pool: ActiveRecord::Base.connection_pool)
        status = status(concurrency:, connection_pool:).merge(
          "hostname" => Socket.gethostname,
          "pid" => Process.pid,
          "updated_at" => Time.current.utc.iso8601(6)
        )
        Sidekiq.redis do |redis|
          redis.hset(key, status.transform_values(&:to_s))
          redis.expire(key, TTL)
        end
        unless status.fetch("valid")
          Rails.logger.warn(
            "Sidekiq database pool is undersized: size=#{status.fetch('size')} " \
            "required=#{status.fetch('required')} concurrency=#{status.fetch('sidekiq_concurrency')}"
          )
        end
        status
      end

      def all(redis:)
        redis.scan_each(match: "#{KEY_PREFIX}:*").map do |worker_key|
          normalize(redis.hgetall(worker_key))
        end
      rescue Redis::BaseError
        []
      end

      def status(concurrency:, connection_pool: ActiveRecord::Base.connection_pool)
        concurrency = Integer(concurrency)
        headroom = [ Integer(ENV.fetch("DB_POOL_HEADROOM", DEFAULT_HEADROOM), exception: false) || DEFAULT_HEADROOM, 1 ].max
        size = connection_pool.size
        required = concurrency + headroom
        {
          "size" => size,
          "sidekiq_concurrency" => concurrency,
          "headroom" => headroom,
          "required" => required,
          "valid" => size >= required
        }
      end

      private

      def key
        "#{KEY_PREFIX}:#{Socket.gethostname}:#{Process.pid}"
      end

      def normalize(status)
        status = status.to_h
        %w[size sidekiq_concurrency headroom required pid].each do |field|
          status[field] = status[field].to_i if status.key?(field)
        end
        status["valid"] = status["valid"] == "true" if status.key?("valid")
        status
      end
    end
  end
end
