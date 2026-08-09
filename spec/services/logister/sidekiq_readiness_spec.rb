# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::SidekiqReadiness do
  it "reports queue age, failure sets, Redis durability, scheduler lateness, and pool sizing" do
    redis = double("redis")
    pool = double("connection_pool", size: 7)
    now = Time.zone.parse("2026-08-08T12:00:00Z")
    allow(redis).to receive(:scard).with("processes").and_return(2)
    allow(redis).to receive(:zcard).with("retry").and_return(3)
    allow(redis).to receive(:zcard).with("dead").and_return(1)
    allow(redis).to receive(:zcard).with("schedule").and_return(8)
    allow(redis).to receive(:llen) { |key| key == "queue:projector" ? 4 : 0 }
    allow(redis).to receive(:lindex) do |key, _index|
      key == "queue:projector" ? { enqueued_at: (now - 90.seconds).to_f }.to_json : nil
    end
    allow(redis).to receive(:hgetall).and_return({})
    allow(redis).to receive(:scan_each).and_return([].each)
    allow(redis).to receive(:info).with("persistence").and_return("aof_enabled" => "1")
    allow(redis).to receive(:info).with("replication").and_return("role" => "master", "connected_slaves" => "1")
    allow(redis).to receive(:config).with(:get, "maxmemory-policy").and_return("maxmemory-policy" => "noeviction")
    allow(redis).to receive(:config).with(:get, "appendonly").and_return("appendonly" => "yes")
    allow(redis).to receive(:config).with(:get, "save").and_return("save" => "3600 1")

    result = described_class.new(redis: redis, concurrency: 5, now: now, connection_pool: pool).call

    expect(result).to include("sidekiq_processes" => 2, "retry_size" => 3, "dead_size" => 1)
    expect(result.dig("queues", "projector")).to include("size" => 4, "age_seconds" => 90)
    expect(result.fetch("redis")).to include(
      "sidekiq_policy_valid" => true,
      "persistence_configured" => true,
      "high_availability_observed" => true
    )
    expect(result.fetch("database_pool")).to include("required" => 7, "valid" => true)
    expect(result.fetch("scheduler")).not_to be_empty
  end
end
