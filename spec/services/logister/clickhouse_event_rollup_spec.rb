# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseEventRollup do
  let(:client) do
    instance_double(
      Logister::ClickhouseClient,
      event_facts_table_name: "logister.event_facts_v2"
    )
  end

  it "builds dashboard event signals with one ClickHouse aggregate query" do
    allow(client).to receive(:select_rows!).and_return(
      [
        { "project_id" => 1, "event_type" => "error", "count" => 2, "latest_event_at" => "2026-07-25 01:00:00.000" },
        { "project_id" => 1, "event_type" => "metric", "count" => 5, "latest_event_at" => "2026-07-25 02:00:00.000" },
        { "project_id" => 2, "event_type" => "log", "count" => 3, "latest_event_at" => "2026-07-25 01:30:00.000" }
      ]
    )

    rollup = described_class.call(project_ids: [ 1, 2 ], since: Time.utc(2026, 7, 24), client:)

    expect(rollup[:event_type_counts]).to include("error" => 2, "metric" => 5, "log" => 3, "transaction" => 0)
    expect(rollup[:active_project_ids]).to contain_exactly(1, 2)
    expect(rollup[:activity_event_counts]).to include(1 => 5, 2 => 3)
    expect(rollup[:latest_event_at_by_project]).to include(
      1 => Time.utc(2026, 7, 25, 2),
      2 => Time.utc(2026, 7, 25, 1, 30)
    )
    expect(client).to have_received(:select_rows!).with(
      a_string_including("count() AS count", "FROM logister.event_facts_v2", "GROUP BY project_id, event_type")
    ).once
  end

  it "lets the range-aware read router own query fallback" do
    allow(client).to receive(:select_rows!).and_raise(Logister::ClickhouseClient::Error, "timeout")

    expect {
      described_class.call(project_ids: [ 1 ], since: 1.day.ago, client:)
    }.to raise_error(Logister::ClickhouseClient::Error, "timeout")
  end
end
