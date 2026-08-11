# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::WorkerPoolHeartbeat do
  it "enumerates worker heartbeats through the Sidekiq Redis Client scan contract" do
    redis = double("sidekiq_redis_client")
    allow(redis).to receive(:call)
      .with("SCAN", "0", "MATCH", "logister:worker_database_pool:*", "COUNT", 100)
      .and_return([ "7", [ "logister:worker_database_pool:archive:1" ] ])
    allow(redis).to receive(:call)
      .with("SCAN", "7", "MATCH", "logister:worker_database_pool:*", "COUNT", 100)
      .and_return([ "0", [] ])
    allow(redis).to receive(:hgetall).and_return(
      "size" => "3",
      "sidekiq_concurrency" => "1",
      "headroom" => "2",
      "required" => "3",
      "valid" => "true",
      "pid" => "42"
    )

    expect(described_class.all(redis: redis)).to contain_exactly(
      hash_including(
        "size" => 3,
        "sidekiq_concurrency" => 1,
        "required" => 3,
        "valid" => true,
        "pid" => 42
      )
    )
  end

  it "validates concurrency plus operational headroom" do
    pool = double("connection_pool", size: 6)

    status = described_class.status(concurrency: 5, connection_pool: pool)

    expect(status).to include(
      "size" => 6,
      "sidekiq_concurrency" => 5,
      "headroom" => 2,
      "required" => 7,
      "valid" => false
    )
  end
end
