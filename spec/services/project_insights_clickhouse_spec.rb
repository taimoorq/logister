# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectInsights do
  it "does not execute PostgreSQL aggregate or percentile paths for a complete ClickHouse range" do
    project = create(:project)
    coverage = instance_double(
      Logister::ClickhouseCoverage::Result,
      complete?: true,
      reason: "complete",
      to_h: { complete: true, reason: "complete" }
    )
    client = instance_double(
      Logister::ClickhouseClient,
      read_enabled?: true,
      event_facts_table_name: "logister.event_facts_v2",
      close: nil
    )
    allow(client).to receive(:select_rows!).and_return(
      [
        {
          "bucket_time" => Time.current.beginning_of_hour.utc.iso8601,
          "events_total" => 2,
          "errors_count" => 0,
          "activity_count" => 2,
          "logs_count" => 1,
          "metrics_count" => 1,
          "check_ins_count" => 0,
          "transactions_count" => 0,
          "transactions_duration_count" => 0,
          "transactions_avg" => 0,
          "transactions_p95" => 0,
          "db_query_count" => 0,
          "db_query_duration_count" => 0,
          "db_query_avg" => 0,
          "db_query_p95" => 0,
          "latest_event_at" => Time.current.utc.iso8601
        }
      ]
    )
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
    allow(Logister::ClickhouseCoverage).to receive(:call).and_return(coverage)
    expect(described_class).not_to receive(:summary_for)
    expect(described_class).not_to receive(:standard_bucket_rows)
    expect(described_class).not_to receive(:postgres_custom_metric_rows)

    payload = described_class.dashboard_for(
      project,
      window: "1h",
      metrics: [ "events.total" ],
      environment: nil,
      release: nil,
      catalog: described_class::BASE_METRICS.values.map(&:dup),
      filter_options: { environments: [], releases: [], attributes: [] }
    )

    expect(payload.fetch(:summary)).to include(events: 2)
    expect(payload.dig(:analytics, :source)).to eq("clickhouse")
    expect(client).to have_received(:close).once
  end
end
