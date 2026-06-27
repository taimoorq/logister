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

  it "uses bound parameters for PostgreSQL advisory locks" do
    connection = double("postgres_connection")
    lock = described_class.new(project_id: 123, dry_run: false)

    allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
    allow(connection).to receive(:adapter_name).and_return("PostgreSQL")

    expect(connection).to receive(:select_value) do |sql, name, binds|
      expect(sql).to eq("SELECT pg_try_advisory_lock($1)")
      expect(name).to eq("ProjectRetentionLock")
      expect(binds.length).to eq(1)
      expect(binds.first.name).to eq("advisory_lock_key")
      expect(binds.first.value_for_database).to be_a(Integer)

      "t"
    end

    expect(lock.acquire).to be(true)

    expect(connection).to receive(:select_value) do |sql, name, binds|
      expect(sql).to eq("SELECT pg_advisory_unlock($1)")
      expect(name).to eq("ProjectRetentionLock")
      expect(binds.length).to eq(1)
      expect(binds.first.name).to eq("advisory_lock_key")
      expect(binds.first.value_for_database).to be_a(Integer)

      "t"
    end

    lock.release
  end
end
