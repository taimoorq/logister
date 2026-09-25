# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectReadCache do
  let(:project) { create(:project, :android) }

  before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

  it "memoizes snapshots only for one request" do
    first = nil
    described_class.set(values: {}) do
      first = ProjectCapabilitySnapshot.for(project)
      expect(ProjectCapabilitySnapshot.for(project)).to equal(first)
    end
    described_class.set(values: {}) { expect(ProjectCapabilitySnapshot.for(project)).not_to equal(first) }
    expect(described_class.values).to be_nil
  end

  it "expires telemetry summaries and separates projects while direct callers stay fresh" do
    calls = 0
    read = ->(target = project) { described_class.fetch(target, :test, shared: true) { calls += 1 } }
    other = create(:project, :android)
    freeze_time do
      described_class.set(values: {}) { expect(read.call).to eq(1) }
      described_class.set(values: {}) { expect(read.call).to eq(1) }
      described_class.set(values: {}) { expect(read.call(other)).to eq(2) }
      expect(read.call).to eq(3)
      travel 31.seconds
      described_class.set(values: {}) { expect(read.call).to eq(4) }
    end
  end

  it "uses cached mobile aggregates on a warm request but refreshes provider failure status" do
    create(:error_occurrence, error_group: create(:error_group, project:), dimensions: { "mapping_status" => "missing" })
    setting = create(:project_integration_setting, project:, provider: "google_play", enabled: true,
      external_project_id: "com.acme.shop", credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS", last_imported_at: 1.minute.ago)
    read = -> { described_class.set(values: {}) { ProjectCapabilitySnapshot.for(project) } }
    cold = capture_sql { expect(read.call.status(:distribution_store).state).to eq(:configured) }
    setting.update!(metadata: { "last_error" => { "at" => Time.current.utc.iso8601, "message" => "denied" } })
    warm = capture_sql { expect(read.call.status(:distribution_store).state).to eq(:failed) }

    expect(cold.grep(/FROM "error_occurrences"/).size).to be >= 2
    expect(warm.grep(/FROM "error_occurrences"/)).to be_empty
  end

  it "falls back once on a cache failure without rerunning a failing database query" do
    allow(Rails.cache).to receive(:fetch).and_raise("cache down")
    calls = 0
    described_class.set(values: {}) do
      expect(described_class.fetch(project, :test, shared: true) { calls += 1 }).to eq(1)
    end
    expect(calls).to eq(1)
    allow(Rails.cache).to receive(:fetch).and_yield
    described_class.set(values: {}) do
      expect { described_class.fetch(project, :test, shared: true) { calls += 1; raise "query failed" } }.to raise_error("query failed")
    end
    expect(calls).to eq(2)
  end
end
