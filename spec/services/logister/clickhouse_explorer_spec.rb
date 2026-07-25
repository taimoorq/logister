# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseExplorer do
  let(:client) do
    instance_double(
      Logister::ClickhouseClient,
      read_enabled?: true,
      events_table_name: "logister.events_raw"
    )
  end

  it "builds every explorer aggregate from one grouped query" do
    allow(client).to receive(:select_rows!).and_return(
      [
        { "day" => "2026-07-24", "project_id" => 1, "event_type" => "error", "environment_name" => "production", "count" => 2 },
        { "day" => "2026-07-25", "project_id" => 1, "event_type" => "metric", "environment_name" => "production", "count" => 5 },
        { "day" => "2026-07-25", "project_id" => 2, "event_type" => "log", "environment_name" => "staging", "count" => 3 }
      ]
    )

    payload = described_class.call(
      project_ids: [ 1, 2 ],
      since: Time.utc(2026, 7, 24),
      environment_limit: 8,
      client:
    )

    expect(payload[:totals]).to eq(events: 10, active_projects: 2, environments: 2)
    expect(payload[:event_types]).to include("error" => 2, "metric" => 5, "log" => 3)
    expect(payload[:timeline]).to include(day: "2026-07-25", event_type: "metric", count: 5)
    expect(payload[:projects]).to eq([ { project_id: 1, count: 7 }, { project_id: 2, count: 3 } ])
    expect(payload[:environments]).to eq([ { name: "production", count: 7 }, { name: "staging", count: 3 } ])
    expect(client).to have_received(:select_rows!).with(a_string_including("uniqExact(event_id) AS count")).once
  end

  it "applies event, environment, and day filters in ClickHouse" do
    allow(client).to receive(:select_rows!).and_return([])

    described_class.call(
      project_ids: [ 1 ],
      since: Time.utc(2026, 7, 20),
      event_type: "log",
      environment: "customer's production",
      occurred_on: Date.new(2026, 7, 24),
      environment_limit: 8,
      client:
    )

    expect(client).to have_received(:select_rows!).with(
      a_string_including(
        "event_type = 'log'",
        "customer\\'s production",
        "2026-07-24T00:00:00.000Z",
        "2026-07-25T00:00:00.000Z"
      )
    )
  end

  it "returns nil so the explorer can fall back when ClickHouse fails" do
    allow(client).to receive(:select_rows!).and_raise(Logister::ClickhouseClient::Error, "timeout")

    expect(
      described_class.call(project_ids: [ 1 ], since: 1.day.ago, environment_limit: 8, client:)
    ).to be_nil
  end
end
