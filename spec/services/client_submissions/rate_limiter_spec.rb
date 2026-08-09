# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientSubmissions::RateLimiter, type: :model do
  it "counts requests in a bounded window" do
    limiter = described_class.new(cache: ActiveSupport::Cache::MemoryStore.new)

    first = limiter.check(identity: "api-key", kind: "accepted", endpoint: "ingest", limit: 1, period: 60)
    second = limiter.check(identity: "api-key", kind: "accepted", endpoint: "ingest", limit: 1, period: 60)

    expect(first).not_to be_limited
    expect(first.remaining).to eq(0)
    expect(second).to be_limited
    expect(second.remaining).to eq(0)
    expect(second.retry_after).to be_positive
  end

  it "does not rate limit when limits are disabled" do
    limiter = described_class.new(cache: ActiveSupport::Cache::MemoryStore.new)

    expect(limiter.check(identity: "api-key", kind: "accepted", endpoint: "ingest", limit: 0, period: 60)).to be_nil
    expect(limiter.check(identity: "api-key", kind: "accepted", endpoint: "ingest", limit: 1, period: 0)).to be_nil
  end

  it "counts every envelope in a batch against tenant volume" do
    limiter = described_class.new(cache: ActiveSupport::Cache::MemoryStore.new)

    batch = limiter.check(
      identity: "api-key",
      kind: "accepted",
      endpoint: "ingest",
      limit: 5,
      period: 60,
      amount: 4
    )
    next_request = limiter.check(
      identity: "api-key",
      kind: "accepted",
      endpoint: "ingest",
      limit: 5,
      period: 60,
      amount: 2
    )

    expect(batch.count).to eq(4)
    expect(batch.remaining).to eq(1)
    expect(next_request).to be_limited
    expect(next_request.count).to eq(6)
  end

  it "shares the coarse pre-auth IP limit across endpoints without counting authentication failures" do
    limiter = described_class.new(cache: ActiveSupport::Cache::MemoryStore.new)

    first_attempt = limiter.check(
      identity: "ip:203.0.113.9",
      kind: "pre_auth",
      endpoint: "ingest",
      limit: 1,
      period: 60
    )
    second_attempt = limiter.check(
      identity: "ip:203.0.113.9",
      kind: "pre_auth",
      endpoint: "check_in",
      limit: 1,
      period: 60
    )
    first_failure = limiter.check(
      identity: "ip:203.0.113.9",
      kind: "auth_failure",
      endpoint: "ingest",
      limit: 1,
      period: 60
    )

    expect(first_attempt).not_to be_limited
    expect(second_attempt).to be_limited
    expect(first_failure).not_to be_limited
    expect(first_failure.count).to eq(1)
  end
end
