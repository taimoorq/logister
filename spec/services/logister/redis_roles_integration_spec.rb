# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Redis role integration", type: :job do
  include ActiveJob::TestHelper

  let(:redis_url) { ENV["REDIS_URL"].presence }
  let(:redis) { Redis.new(url: redis_url) }
  let(:probe_queue) { "phase_one_ci_probe_#{Process.pid}" }
  let(:recurring_key) { "phase_one_ci_recurring_probe_#{Process.pid}" }
  let(:recurring_job_class) do
    job_class = Class.new(ApplicationJob) do
      include SidekiqRecurringJob
      queue_as :projector

      def perform; end
    end
    stub_const("PhaseOneRedisRecurringProbeJob", job_class)
    job_class.sidekiq_recurring_schedule(key: recurring_key, every: 15.minutes)
    job_class
  end

  before do
    skip "REDIS_URL is required for the live Redis integration spec" unless redis_url
    skip "Redis is not reachable" unless redis.ping == "PONG"
  rescue Redis::BaseError
    skip "Redis is not reachable"
  end

  after do
    next unless redis_url

    redis.scan_each(match: "logister:test:redis_roles:*").to_a.then { |keys| redis.del(*keys) if keys.any? }
    redis.scan_each(match: "logister:sidekiq_recurring:scheduled:#{recurring_key}:*").to_a.then { |keys| redis.del(*keys) if keys.any? }
    redis.del("queue:#{probe_queue}")
    redis.srem("queues", probe_queue)
    redis.close
  rescue Redis::BaseError
    nil
  end

  it "supports cache and rate-limit counters without sharing Rails.cache" do
    cache = ActiveSupport::Cache::RedisCacheStore.new(url: redis_url, namespace: "logister:test:redis_roles:cache")
    rate_limit_cache = ActiveSupport::Cache::RedisCacheStore.new(url: redis_url, namespace: "logister:test:redis_roles:rate_limit")
    limiter = ClientSubmissions::RateLimiter.new(cache: rate_limit_cache)

    cache.write("probe", "ok", expires_in: 1.minute)
    first = limiter.check(identity: "project-1", kind: "accepted", endpoint: "events", limit: 1, period: 60)
    second = limiter.check(identity: "project-1", kind: "accepted", endpoint: "events", limit: 1, period: 60)

    expect(cache.read("probe")).to eq("ok")
    expect(first).not_to be_limited
    expect(second).to be_limited
  end

  it "persists Sidekiq work in the configured Redis" do
    jid = Sidekiq::Client.push("class" => "PhaseOneRedisProbeJob", "args" => [], "queue" => probe_queue)
    jobs = redis.lrange("queue:#{probe_queue}", 0, -1).map { |payload| JSON.parse(payload) }

    expect(jid).to be_present
    expect(jobs).to include(hash_including("jid" => jid, "queue" => probe_queue))
  end

  it "deduplicates recurring schedule lookahead keys through live Redis" do
    clear_enqueued_jobs

    recurring_job_class.ensure_scheduled!(Time.zone.parse("2026-08-08T12:10:30Z"), occurrences: 2)
    recurring_job_class.ensure_scheduled!(Time.zone.parse("2026-08-08T12:10:30Z"), occurrences: 2)

    expect(enqueued_jobs.count { |job| job[:job] == recurring_job_class }).to eq(2)
  end
end
