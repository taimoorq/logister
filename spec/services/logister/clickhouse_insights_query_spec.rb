# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseInsightsQuery do
  let(:project) { instance_double(Project, id: 42) }
  let(:client) do
    instance_double(
      Logister::ClickhouseClient,
      event_facts_table_name: "logister.event_facts_v2"
    )
  end

  it "normalizes ClickHouse numerics and custom metric rows into the PostgreSQL contract" do
    allow(client).to receive(:select_rows!).and_return(
      [
        {
          "bucket_time" => "2026-08-08 11:00:00",
          "events_total" => "3",
          "errors_count" => "1",
          "activity_count" => "2",
          "logs_count" => "0",
          "metrics_count" => "2",
          "check_ins_count" => "0",
          "transactions_count" => "0",
          "transactions_duration_count" => "0",
          "transactions_avg" => "0",
          "transactions_p95" => "0",
          "db_query_count" => "1",
          "db_query_duration_count" => "1",
          "db_query_avg" => "12.5",
          "db_query_p95" => "12.5",
          "latest_event_at" => "2026-08-08 11:45:00"
        }
      ],
      [
        {
          "bucket_time" => "2026-08-08 11:00:00",
          "metric_name" => "queue.depth",
          "event_count" => "2",
          "numeric_count" => "2",
          "value_avg" => "8.0"
        }
      ]
    )

    result = described_class.new(
      project:,
      since: Time.utc(2026, 8, 8, 10),
      to: Time.utc(2026, 8, 8, 12),
      bucket: "hour",
      custom_metric_names: [ "queue.depth" ],
      client:
    ).call

    expect(result.fetch(:summary)).to include(events: 3, errors: 1, metrics: 2)
    expect(result.fetch(:standard_bucket_rows).first).to include(
      "bucket_time" => "2026-08-08T11:00:00Z",
      "events_total" => 3,
      "db_query_avg" => 12.5
    )
    expect(result.fetch(:custom_metric_rows)).to contain_exactly(
      "bucket_time" => "2026-08-08T11:00:00Z",
      "metric_name" => "queue.depth",
      "event_count" => 2,
      "numeric_count" => 2,
      "value_avg" => 8.0
    )
    expect(client).to have_received(:select_rows!).with(a_string_including("FROM logister.event_facts_v2")).twice
  end
end
