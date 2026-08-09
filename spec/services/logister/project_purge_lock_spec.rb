# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ProjectPurgeLock, type: :model do
  it "admits only one owner with the cache fallback" do
    cache = ActiveSupport::Cache::MemoryStore.new
    first = described_class.new(project_purge_id: 123, cache: cache)
    second = described_class.new(project_purge_id: 123, cache: cache)
    allow(first).to receive(:postgresql?).and_return(false)
    allow(second).to receive(:postgresql?).and_return(false)

    expect(first.acquire).to be(true)
    expect(second.acquire).to be(false)
    first.release
    expect(second.acquire).to be(true)
  ensure
    first&.release
    second&.release
  end

  it "uses a bound session advisory lock for PostgreSQL" do
    connection = double("postgres_connection")
    lock = described_class.new(project_purge_id: 123)
    allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
    allow(connection).to receive(:adapter_name).and_return("PostgreSQL")

    expect(connection).to receive(:select_value) do |sql, name, binds|
      expect(sql).to eq("SELECT pg_try_advisory_lock($1)")
      expect(name).to eq("ProjectPurgeLock")
      expect(binds.first.name).to eq("advisory_lock_key")
      "t"
    end
    expect(lock.acquire).to be(true)
    expect(connection).to receive(:select_value).with(
      "SELECT pg_advisory_unlock($1)",
      "ProjectPurgeLock",
      array_including(have_attributes(name: "advisory_lock_key"))
    ).and_return("t")
    lock.release
  end
end
