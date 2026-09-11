# frozen_string_literal: true

require "rails_helper"
require "sidekiq/redis_connection"
require "socket"
require "tmpdir"

RSpec.describe "Production core worker capacity" do
  it "runs every general queue while real projector threads are blocked" do
    Dir.mktmpdir("logister-sidekiq-capacity") do |directory|
      socket = TCPServer.new("127.0.0.1", 0)
      port = socket.addr[1]
      socket.close
      log = File.join(directory, "processes.log")
      redis_pid = Process.spawn("redis-server", "--bind", "127.0.0.1", "--port", port.to_s,
        "--save", "", "--appendonly", "no", out: log, err: [ :child, :out ])
      redis_url = "redis://127.0.0.1:#{port}/0"
      redis = Redis.new(url: redis_url, connect_timeout: 1, read_timeout: 1)
      await_condition(log) { redis.ping == "PONG" rescue false }
      environment = {
        "RAILS_ENV" => "test", "SIDEKIQ_CONCURRENCY" => "5", "SIDEKIQ_PROJECTOR_CONCURRENCY" => "3",
        "REDIS_URL" => redis_url, "REDIS_SIDEKIQ_URL" => redis_url,
        "REDIS_CACHE_URL" => redis_url, "REDIS_RATE_LIMIT_URL" => redis_url
      }
      worker_pid = Process.spawn(environment, RbConfig.ruby, "-S", "bundle", "exec", "sidekiq",
        "-e", "test", "-C", "config/sidekiq-core.yml", "-r", "./spec/fixtures/sidekiq_capacity_boot.rb",
        "-t", "2", chdir: Rails.root.to_s, out: [ log, "a" ], err: [ :child, :out ])
      pool = Sidekiq::RedisConnection.create(url: redis_url, size: 1)
      client = Sidekiq::Client.new(pool: pool)
      token = "capacity:#{SecureRandom.hex(8)}"
      6.times { client.push("class" => "CapacityBlockingJob", "queue" => "projector", "args" => [ token ]) }
      await_condition(log) { redis.get("#{token}:started").to_i == 3 }

      queues = %w[notifications mailers analytics integrations symbols maintenance default]
      (queues + [ "archives" ]).each do |queue|
        client.push("class" => "CapacitySentinelJob", "queue" => queue, "args" => [ token, queue ])
      end
      await_condition(log, seconds: 10) { redis.hlen("#{token}:completed") == queues.size }

      expect(redis.hgetall("#{token}:completed")).to eq(queues.to_h { |queue| [ queue, "5" ] })
      expect(redis.get("#{token}:started").to_i).to eq(3)
      expect(redis.llen("queue:projector")).to eq(3)
      expect(redis.llen("queue:archives")).to eq(1)
    ensure
      redis&.set("#{token}:release", "1") if token
      stop_process(worker_pid)
      pool&.shutdown(&:close)
      redis&.close
      stop_process(redis_pid)
    end
  end

  def await_condition(log, seconds: 30)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until yield
      raise "Sidekiq capacity probe timed out:\n#{File.read(log).last(8_000)}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end

  def stop_process(pid)
    return unless pid

    Process.kill("TERM", pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until Process.waitpid(pid, Process::WNOHANG)
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        Process.kill("KILL", pid)
        Process.waitpid(pid)
        break
      end
      sleep 0.05
    end
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end
end
