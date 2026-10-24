# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::RateLimitCounter do
  let(:fallback_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:events) { [] }

  around do |example|
    subscriber = ActiveSupport::Notifications.subscribe(described_class::DEGRADED_EVENT) do |*, payload|
      events << payload
    end
    example.run
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "counts in the shared store when it is healthy" do
    store = ActiveSupport::Cache::MemoryStore.new
    counter = described_class.new(store: store, fallback_store: fallback_store)

    expect(counter.increment("key", expires_in: 60, kind: "pre_auth")).to eq(1)
    expect(counter.increment("key", amount: 2, expires_in: 60, kind: "pre_auth")).to eq(3)
    expect(fallback_store.read("key")).to be_nil
    expect(events).to be_empty
  end

  it "falls back to the bounded in-process store and reports the degradation when the shared store raises" do
    allow(Rails.logger).to receive(:warn).and_call_original
    counter = described_class.new(store: unavailable_rate_limit_store, fallback_store: fallback_store)

    expect(counter.increment("key", expires_in: 60, kind: "auth_failure")).to eq(1)
    expect(counter.increment("key", expires_in: 60, kind: "auth_failure")).to eq(2)

    expect(events.size).to eq(2)
    expect(events.first).to include(kind: "auth_failure", error_class: "Errno::ECONNREFUSED", fallback: "memory")
    expect(Rails.logger).to have_received(:warn).with(/rate limit store unavailable for auth_failure, using in-process fallback/).twice
  end

  it "treats a store that swallows errors and refuses the write as unavailable" do
    swallowing_store = Class.new do
      def increment(*, **) = nil
      def write(*, **) = false
    end.new
    counter = described_class.new(store: swallowing_store, fallback_store: fallback_store)

    expect(counter.increment("key", expires_in: 60, kind: "accepted")).to eq(1)
    expect(counter.increment("key", expires_in: 60, kind: "accepted")).to eq(2)
    expect(events.first).to include(error_class: "Logister::RateLimitCounter::StoreUnavailable", fallback: "memory")
  end

  it "returns nil so callers fail closed when the fallback store also fails" do
    counter = described_class.new(
      store: unavailable_rate_limit_store,
      fallback_store: unavailable_rate_limit_store("fallback unavailable")
    )

    expect(counter.increment("key", expires_in: 60, kind: "cli_device_create")).to be_nil
    expect(events.sole).to include(kind: "cli_device_create", fallback: "none", fallback_error_class: "Errno::ECONNREFUSED")
  end

  it "caps the process-wide fallback store" do
    store = described_class.fallback_store

    expect(store).to be_a(ActiveSupport::Cache::MemoryStore)
    expect(store.instance_variable_get(:@max_size)).to eq(described_class::FALLBACK_STORE_SIZE)
    expect(described_class.fallback_store).to equal(store)
  end
end
