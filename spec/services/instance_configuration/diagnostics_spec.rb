# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstanceConfiguration::Diagnostics, type: :model do
  it "validates the required general settings without a network call" do
    result = described_class.call("general", values: InstanceConfiguration.values_for("general"))

    expect(result).to be_success
    expect(result.summary).to include("Canonical URLs")
  end

  it "requires both Redis and a registered Sidekiq worker" do
    redis = instance_double(Redis, ping: "PONG", scard: 0, close: nil)
    allow(Redis).to receive(:new).and_return(redis)

    result = described_class.call("background_jobs", values: InstanceConfiguration.values_for("background_jobs"))

    expect(result).not_to be_success
    expect(result.summary).to include("no Sidekiq worker")

    allow(redis).to receive(:scard).and_return(2)
    result = described_class.call("background_jobs", values: InstanceConfiguration.values_for("background_jobs"))

    expect(result).to be_success
    expect(result.details).to include("sidekiq_processes" => 2)
  end

  it "does a write, read, and cleanup check for local archives" do
    result = described_class.call("archive_storage", values: InstanceConfiguration.values_for("archive_storage"))

    expect(result).to be_success
    expect(result.summary).to include("write, read, and delete")
    expect(Dir.glob(Rails.root.join("storage/.logister-configuration-test-*"))).to be_empty
  end

  it "does not declare ClickHouse read-ready when retained coverage is short" do
    values = InstanceConfiguration.values_for(
      "clickhouse",
      overrides: { "clickhouse.mode" => "dual_write", "clickhouse.url" => "https://clickhouse.example" }
    )
    client = instance_double(
      Logister::ClickhouseClient,
      schema_status: { ready: true, healthy: true, database: "logister", missing_tables: [], schema_issues: [] },
      events_table_name: "logister.events_raw"
    )
    allow(client).to receive(:select_rows!).and_return([ { "count" => 0 } ])
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
    create(:ingest_event, occurred_at: 1.hour.ago)

    result = described_class.call("clickhouse", values: values)

    expect(result).not_to be_success
    expect(result.details).to include("ready_for_reads" => false)
    expect(client).to have_received(:select_rows!).with(a_string_including("uniqExact(event_id)"))
  end

  it "tells an operator to finish the read cutover when dual-write coverage passes" do
    values = InstanceConfiguration.values_for(
      "clickhouse",
      overrides: { "clickhouse.mode" => "dual_write", "clickhouse.url" => "https://clickhouse.example" }
    )
    client = instance_double(
      Logister::ClickhouseClient,
      schema_status: { ready: true, healthy: true, database: "logister", missing_tables: [], schema_issues: [] },
      events_table_name: "logister.events_raw"
    )
    allow(client).to receive(:select_rows!).and_return([ { "count" => 1 } ])
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
    create(:ingest_event, occurred_at: 1.hour.ago)

    result = described_class.call("clickhouse", values: values)

    expect(result).to be_success
    expect(result.summary).to include("Switch to read preferred", "dashboard reads off PostgreSQL")
  end

  it "rejects nonpositive public API limits" do
    values = InstanceConfiguration.values_for(
      "authentication",
      overrides: { "authentication.public_api_rate_limit_requests" => "0" }
    )

    result = described_class.call("authentication", values: values)

    expect(result).not_to be_success
    expect(result.summary).to include("positive integers")
  end
end
