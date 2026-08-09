# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe Logister::ClickhouseCircuitBreaker do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:config) do
    OpenStruct.new(
      clickhouse_url: "https://clickhouse.example",
      clickhouse_database: "logister",
      clickhouse_circuit_failure_threshold: 2,
      clickhouse_circuit_open_seconds: 30
    )
  end
  let(:clock_time) { Time.zone.parse("2026-08-08T12:00:00Z") }
  let(:clock) { -> { clock_time } }

  it "moves from closed to open, allows one half-open probe, and closes on success" do
    breaker = described_class.new(config: config, cache: cache, clock: clock)

    expect(breaker.status).to include("state" => "closed")
    breaker.record_failure!(error: Timeout::Error.new("one"))
    expect(breaker.allow_request?).to be(true)
    breaker.record_failure!(error: Timeout::Error.new("two"))

    expect(breaker.status).to include("state" => "open", "failure_count" => 2)
    expect(breaker.allow_request?).to be(false)

    allow(clock).to receive(:call).and_return(clock_time + 31.seconds)
    expect(breaker.status).to include("state" => "half_open")
    expect(breaker.allow_request?).to be(true)
    expect(breaker.allow_request?).to be(false)

    breaker.record_success!
    expect(breaker.status).to include("state" => "closed", "failure_count" => 0)
  end

  it "fails open when the cache is unavailable" do
    allow(cache).to receive(:read).and_raise(Redis::CannotConnectError, "unavailable")
    breaker = described_class.new(config: config, cache: cache, clock: clock)

    expect(breaker.allow_request?).to be(true)
    expect(breaker.status).to include("state" => "unknown")
  end
end
