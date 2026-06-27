# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ProjectRetentionLock, type: :model do
  it "serializes non-dry-run retention with the cache fallback" do
    cache = ActiveSupport::Cache::MemoryStore.new
    first_lock = described_class.new(project_id: 123, dry_run: false, cache: cache)
    second_lock = described_class.new(project_id: 123, dry_run: false, cache: cache)

    allow(first_lock).to receive(:postgresql?).and_return(false)
    allow(second_lock).to receive(:postgresql?).and_return(false)

    expect(first_lock.acquire).to be(true)
    expect(second_lock.acquire).to be(false)

    first_lock.release

    expect(second_lock.acquire).to be(true)
  ensure
    second_lock&.release
  end

  it "does not lock dry runs" do
    cache = instance_spy(ActiveSupport::Cache::MemoryStore)
    lock = described_class.new(project_id: 123, dry_run: true, cache: cache)

    expect(lock.acquire).to be(true)
    lock.release

    expect(cache).not_to have_received(:write)
  end
end
