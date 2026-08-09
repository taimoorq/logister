# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ClickHouse schema v2" do
  let(:schema) { Rails.root.join("docs/clickhouse_schema.sql").read }

  it "defines typed facts and replay-safe logical rollups" do
    expect(schema).to include(
      "identity_checksum UInt128",
      "metric_value Nullable(Float64)",
      "transaction_status LowCardinality(String)",
      "check_in_status LowCardinality(String)",
      "http_status_code Nullable(UInt16)",
      "CREATE VIEW IF NOT EXISTS logister.event_facts_v2",
      "LIMIT 1 BY project_id, event_id",
      "CREATE VIEW IF NOT EXISTS logister.span_facts_v2",
      "LIMIT 1 BY project_id, span_id",
      "metric_facts_1m_v2",
      "metric_facts_1h_v2",
      "transaction_facts_1m_v2",
      "transaction_facts_1h_v2",
      "request_span_facts_1m_v2",
      "request_span_facts_1h_v2"
    )
  end

  it "does not feed aggregates directly from the at-least-once append tables" do
    expect(schema).not_to include("CREATE MATERIALIZED VIEW")
    expect(schema).not_to include("AggregatingMergeTree")
  end

  it "keeps raw facts beyond the maximum watermark/read horizon" do
    expect(schema.scan("INTERVAL 120 DAY DELETE").length).to eq(4)
    expect(schema).not_to include("INTERVAL 90 DAY DELETE")
    expect(TelemetryProjectionWatermark::RETENTION).to eq(90.days)
  end
end
