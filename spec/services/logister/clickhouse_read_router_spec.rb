# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseReadRouter do
  let(:started_at) { Time.utc(2026, 8, 8, 10) }
  let(:ended_at) { Time.utc(2026, 8, 8, 12) }
  let(:client) { instance_double(Logister::ClickhouseClient, read_enabled?: true) }
  let(:reconciler) do
    instance_double(
      Logister::ClickhouseDualReadReconciler,
      sampled?: false,
      skipped: Logister::ClickhouseDualReadReconciler::Result.new(false, nil, nil, nil, nil)
    )
  end

  def coverage(complete:, reason:)
    instance_double(Logister::ClickhouseCoverage::Result, complete?: complete, reason: reason, to_h: { complete:, reason: })
  end

  it "routes an incomplete range to PostgreSQL without querying ClickHouse" do
    clickhouse = -> { raise "must not run" }
    postgres = -> { { events: 9 } }

    result = described_class.call(
      project_ids: [ 1 ], signals: [ "metric" ], from: started_at, to: ended_at,
      clickhouse:, postgres:, client:, coverage: coverage(complete: false, reason: "incomplete_watermarks"), reconciler:
    )

    expect(result.source).to eq("postgresql")
    expect(result.payload).to eq(events: 9)
    expect(result.diagnostics).to include(fallback_reason: "incomplete_watermarks")
  end

  it "routes a complete range to ClickHouse" do
    postgres = -> { raise "shadow should not run when unsampled" }

    result = described_class.call(
      project_ids: [ 1 ], signals: [ "metric" ], from: started_at, to: ended_at,
      clickhouse: -> { { events: 9 } }, postgres:, client:,
      coverage: coverage(complete: true, reason: "complete"), reconciler:
    )

    expect(result).to be_clickhouse
    expect(result.payload).to eq(events: 9)
    expect(result.diagnostics).to include(source: "clickhouse")
  end

  it "keeps PostgreSQL as the exception fallback after completeness passes" do
    result = described_class.call(
      project_ids: [ 1 ], signals: [ "span" ], from: started_at, to: ended_at,
      clickhouse: -> { raise Logister::ClickhouseClient::Error, "timeout" },
      postgres: -> { { requests: [] } }, client:,
      coverage: coverage(complete: true, reason: "complete"), reconciler:
    )

    expect(result.source).to eq("postgresql")
    expect(result.fallback_reason).to include("clickhouse_query_failed")
  end

  it "closes a short-lived client that the router owns" do
    owned_client = instance_double(Logister::ClickhouseClient, read_enabled?: false, close: nil)
    allow(Logister::ClickhouseClient).to receive(:new).and_return(owned_client)

    described_class.call(
      project_ids: [ 1 ], signals: [ "metric" ], from: started_at, to: ended_at,
      clickhouse: -> { raise "must not run" }, postgres: -> { {} }, reconciler:
    )

    expect(owned_client).to have_received(:close).once
  end
end
