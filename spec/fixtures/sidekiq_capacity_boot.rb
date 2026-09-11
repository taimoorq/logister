# frozen_string_literal: true

require_relative "../../config/environment"

class CapacityBlockingJob
  include Sidekiq::Job

  def perform(token)
    Sidekiq.redis { |redis| redis.incr("#{token}:started") }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    loop do
      break if Sidekiq.redis { |redis| redis.get("#{token}:release") }
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end
end

class CapacitySentinelJob
  include Sidekiq::Job

  def perform(token, queue)
    Sidekiq.redis do |redis|
      redis.hset("#{token}:completed", queue, Sidekiq.default_configuration.total_concurrency)
    end
  end
end
