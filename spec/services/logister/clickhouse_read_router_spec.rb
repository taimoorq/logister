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

  def postgres_coverage_service(complete:)
    result = Logister::PostgresRetentionCoverage::Result.new(
      complete,
      complete ? "within_postgres_retention" : "postgres_retention_window",
      started_at,
      ended_at,
      started_at + 1.hour
    )
    class_double(Logister::PostgresRetentionCoverage, call: result)
  end

  it "routes an incomplete range to PostgreSQL without querying ClickHouse" do
    clickhouse = -> { raise "must not run" }
    postgres = -> { { events: 9 } }

    fallback_coverage = postgres_coverage_service(complete: false)
    result = described_class.call(
      project_ids: [ 1 ], signals: [ "metric" ], from: started_at, to: ended_at,
      clickhouse:, postgres:, client:, coverage: coverage(complete: false, reason: "incomplete_watermarks"),
      postgres_coverage_service: fallback_coverage, reconciler:
    )

    expect(result.source).to eq("postgresql")
    expect(result.payload).to eq(events: 9)
    expect(result).to be_partial
    expect(result.diagnostics).to include(
      fallback_reason: "incomplete_watermarks",
      partial: true,
      fallback_coverage: include(complete: false, reason: "postgres_retention_window")
    )
  end

  it "routes a complete range to ClickHouse" do
    postgres = -> { raise "shadow should not run when unsampled" }

    fallback_coverage = postgres_coverage_service(complete: true)
    result = described_class.call(
      project_ids: [ 1 ], signals: [ "metric" ], from: started_at, to: ended_at,
      clickhouse: -> { { events: 9 } }, postgres:, client:,
      coverage: coverage(complete: true, reason: "complete"),
      postgres_coverage_service: fallback_coverage, reconciler:
    )

    expect(result).to be_clickhouse
    expect(result).not_to be_partial
    expect(result.payload).to eq(events: 9)
    expect(result.diagnostics).to include(source: "clickhouse", partial: false)
    expect(result.diagnostics).not_to have_key(:fallback_coverage)
    expect(fallback_coverage).not_to have_received(:call)
  end

  it "keeps PostgreSQL as the exception fallback after completeness passes" do
    result = described_class.call(
      project_ids: [ 1 ], signals: [ "span" ], from: started_at, to: ended_at,
      clickhouse: -> { raise Logister::ClickhouseClient::Error, "timeout" },
      postgres: -> { { requests: [] } }, client:,
      coverage: coverage(complete: true, reason: "complete"),
      postgres_coverage_service: postgres_coverage_service(complete: false), reconciler:
    )

    expect(result.source).to eq("postgresql")
    expect(result).to be_partial
    expect(result.fallback_reason).to include("clickhouse_query_failed")
  end

  it "does not report a complete PostgreSQL fallback as partial" do
    result = described_class.call(
      project_ids: [ 1 ], signals: [ "metric" ], from: started_at, to: ended_at,
      clickhouse: -> { raise "must not run" }, postgres: -> { { events: 3 } }, client:,
      coverage: coverage(complete: false, reason: "incomplete_watermarks"),
      postgres_coverage_service: postgres_coverage_service(complete: true), reconciler:
    )

    expect(result).not_to be_partial
    expect(result.diagnostics).to include(
      partial: false,
      fallback_coverage: include(complete: true, reason: "within_postgres_retention")
    )
  end

  it "closes a short-lived client that the router owns" do
    owned_client = instance_double(Logister::ClickhouseClient, read_enabled?: false, close: nil)
    allow(Logister::ClickhouseClient).to receive(:new).and_return(owned_client)

    described_class.call(
      project_ids: [ 1 ], signals: [ "metric" ], from: started_at, to: ended_at,
      clickhouse: -> { raise "must not run" }, postgres: -> { {} },
      postgres_coverage_service: postgres_coverage_service(complete: true), reconciler:
    )

    expect(owned_client).to have_received(:close).once
  end
end
