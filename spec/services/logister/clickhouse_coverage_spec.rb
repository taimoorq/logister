# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseCoverage do
  Watermark = Struct.new(:project_id, :signal, :bucket_start_at, :last_delivered_at, :complete_value) do
    def complete? = complete_value
  end

  let(:started_at) { Time.utc(2026, 8, 8, 10) }
  let(:ended_at) { Time.utc(2026, 8, 8, 12) }
  let(:repository) { instance_double(Logister::ClickhouseCoverage::Repository) }

  it "requires explicit evidence for every requested hour even after source retention" do
    allow(repository).to receive(:watermarks).and_return(
      [ Watermark.new(7, "metric", started_at, started_at + 5.minutes, true) ]
    )

    result = described_class.call(
      project_ids: [ 7 ], signals: [ "metric" ], from: started_at, to: ended_at, repository:
    )

    expect(result).not_to be_complete
    expect(result.reason).to eq("incomplete_watermarks")
    expect(result.to_h).to include(required_bucket_count: 2, complete_bucket_count: 1, coverage_ratio: 0.5)
    expect(result.incomplete_buckets).to contain_exactly(
      project_id: 7, signal: "metric", bucket_start_at: (started_at + 1.hour).iso8601
    )
  end

  it "marks a range complete only when every required bucket is complete" do
    watermark = Watermark.new(7, "span", started_at, started_at + 10.minutes, true)
    allow(repository).to receive(:watermarks).and_return([ watermark ])

    result = described_class.call(
      project_ids: [ 7 ], signals: [ "span" ], from: started_at, to: started_at + 1.hour, repository:
    )

    expect(result).to be_complete
    expect(result.to_h).to include(
      reason: "complete",
      coverage_ratio: 1.0,
      fresh_through: (started_at + 1.hour).iso8601
    )
  end

  it "fails closed when neither retained source rows nor durable watermarks prove coverage" do
    allow(repository).to receive(:watermarks).and_return([])

    result = described_class.call(
      project_ids: [ 7 ], signals: [ "log" ], from: started_at, to: ended_at, repository:
    )

    expect(result).not_to be_complete
    expect(result.reason).to eq("no_coverage_evidence")
    expect(result.coverage_ratio).to eq(0.0)
  end

  it "enumerates the complete project, signal, and overlapping-hour cross product" do
    allow(repository).to receive(:watermarks).and_return([])

    result = described_class.call(
      project_ids: [ 7, 8 ],
      signals: [ "metric", "span" ],
      from: started_at + 30.minutes,
      to: ended_at + 15.minutes,
      repository: repository
    )

    expect(result.required_bucket_count).to eq(12)
    expect(result.incomplete_buckets).to include(
      project_id: 8,
      signal: "span",
      bucket_start_at: ended_at.iso8601
    )
  end

  it "does not allow a watermark with the wrong signal destination to satisfy coverage" do
    project = create(:project)
    TelemetryProjectionWatermark.create!(
      project: project,
      signal: "span",
      destination: "clickhouse_event",
      bucket_start_at: started_at,
      complete_at: started_at,
      accepted_count: 0,
      delivered_count: 0
    )

    result = described_class.call(
      project_ids: [ project.id ],
      signals: [ "span" ],
      from: started_at,
      to: started_at + 1.hour
    )

    expect(result).not_to be_complete
    expect(result.reason).to eq("no_coverage_evidence")
  end
end
