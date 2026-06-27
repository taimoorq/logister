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
end
