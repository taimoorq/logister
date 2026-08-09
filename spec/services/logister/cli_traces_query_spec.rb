# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::CliTracesQuery do
  let(:project) { create(:project) }
  let(:api_key) { create(:api_key, project:, user: project.user) }
  let(:since_at) { 1.hour.ago }
  let(:until_at) { 1.minute.from_now }
  let(:skipped_reconciliation) { Logister::ClickhouseDualReadReconciler::Result.new(false, nil, nil, nil, nil) }
  let(:reconciler) do
    instance_double(
      Logister::ClickhouseDualReadReconciler,
      sampled?: false,
      skipped: skipped_reconciliation
    )
  end

  before do
    allow(Logister::ClickhouseDualReadReconciler).to receive(:new).and_return(reconciler)
  end

  def coverage(complete:, reason:)
    instance_double(
      Logister::ClickhouseCoverage::Result,
      complete?: complete,
      reason:,
      to_h: { complete:, reason: }
    )
  end

  def client(read_enabled: true)
    instance_double(
      Logister::ClickhouseClient,
      read_enabled?: read_enabled,
      span_facts_table_name: "span_facts_v2",
      close: nil
    )
  end

  it "uses complete ClickHouse trace coverage and redacts returned context" do
    clickhouse = client
    row = {
      "uuid" => SecureRandom.uuid,
      "trace_id" => "trace-clickhouse",
      "external_span_id" => "root",
      "parent_span_id" => "",
      "name" => "GET /checkout",
      "route" => "GET /checkout",
      "kind" => "server",
      "status" => "unexpected-old-status",
      "duration_ms" => "12.5",
      "started_at" => Time.current.iso8601(6),
      "ended_at" => 0.0125.seconds.from_now.iso8601(6),
      "environment" => "production",
      "release" => "1.0.0",
      "service" => "web",
      "request_id" => "req-1",
      "context_json" => { password: "secret", safe: "kept" }.to_json
    }
    allow(clickhouse).to receive(:select_rows!).and_return([ row ])
    allow(Logister::ClickhouseClient).to receive(:new).and_return(clickhouse)
    allow(Logister::ClickhouseCoverage).to receive(:call).and_return(coverage(complete: true, reason: "complete"))

    result = described_class.trace(
      project:,
      trace_id: "trace-clickhouse",
      since: since_at,
      to: until_at
    )

    expect(result.read.source).to eq("clickhouse")
    expect(result.items.sole).to include(status: "unset")
    expect(result.items.sole.dig(:context, "password")).to eq("[REDACTED]")
    expect(result.items.sole.dig(:context, "safe")).to eq("kept")
  end

  it "uses PostgreSQL without querying ClickHouse for incomplete coverage" do
    span = create(:trace_span, project:, api_key:, trace_id: "trace-postgres")
    clickhouse = client
    allow(clickhouse).to receive(:select_rows!)
    allow(Logister::ClickhouseClient).to receive(:new).and_return(clickhouse)
    allow(Logister::ClickhouseCoverage).to receive(:call).and_return(
      coverage(complete: false, reason: "incomplete_watermarks")
    )

    result = described_class.list(
      project:,
      since: since_at,
      to: until_at,
      filters: {},
      cursor: nil,
      limit: 10
    )

    expect(result.read.source).to eq("postgresql")
    expect(result.items.pluck(:uuid)).to include(span.uuid)
    expect(clickhouse).not_to have_received(:select_rows!)
  end

  it "uses PostgreSQL when ClickHouse reads are disabled" do
    span = create(:trace_span, project:, api_key:, trace_id: "trace-disabled")
    clickhouse = client(read_enabled: false)
    allow(Logister::ClickhouseClient).to receive(:new).and_return(clickhouse)
    allow(Logister::ClickhouseCoverage).to receive(:call)

    result = described_class.list(
      project:,
      since: since_at,
      to: until_at,
      filters: {},
      cursor: nil,
      limit: 10
    )

    expect(result.read.source).to eq("postgresql")
    expect(result.items.pluck(:uuid)).to include(span.uuid)
    expect(Logister::ClickhouseCoverage).not_to have_received(:call)
  end

  it "falls back to PostgreSQL when a complete-coverage ClickHouse query fails" do
    span = create(:trace_span, project:, api_key:, trace_id: "trace-failure")
    clickhouse = client
    allow(clickhouse).to receive(:select_rows!).and_raise(Logister::ClickhouseClient::Error, "timeout")
    allow(Logister::ClickhouseClient).to receive(:new).and_return(clickhouse)
    allow(Logister::ClickhouseCoverage).to receive(:call).and_return(coverage(complete: true, reason: "complete"))

    result = described_class.list(
      project:,
      since: since_at,
      to: until_at,
      filters: {},
      cursor: nil,
      limit: 10
    )

    expect(result.read.source).to eq("postgresql")
    expect(result.read.fallback_reason).to include("clickhouse_query_failed")
    expect(result.items.pluck(:uuid)).to include(span.uuid)
  end
end
