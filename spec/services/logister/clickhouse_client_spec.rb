# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe Logister::ClickhouseClient do
  let(:config) do
    OpenStruct.new(
      clickhouse_enabled: true,
      clickhouse_url: "https://clickhouse.example.com",
      clickhouse_database: "logister",
      clickhouse_events_table: "events",
      clickhouse_spans_table: "spans",
      clickhouse_username: nil,
      clickhouse_password: nil
    )
  end

  describe "#insert_event!" do
    it "raises when ClickHouse returns a non-success response" do
      client = described_class.new(config: config)
      response = instance_double(Net::HTTPResponse, code: "500", body: "boom")
      allow(client).to receive(:post_query).and_return(response)

      expect {
        client.insert_event!({ event_id: "abc123" })
      }.to raise_error(Logister::ClickhouseClient::Error, /500 boom/)
    end

    it "uses query api request bodies for clickhouse cloud endpoints" do
      query_api_config = config.dup
      query_api_config.clickhouse_url = "https://queries.clickhouse.cloud/service/123/run"
      client = described_class.new(config: query_api_config)

      body = client.send(:request_body, "SELECT 1 FORMAT TabSeparated", "{\"ok\":true}\n")

      expect(JSON.parse(body)).to eq(
        "sql" => "SELECT 1 FORMAT TabSeparated\n{\"ok\":true}\n"
      )
    end
  end

  describe "#insert_span!" do
    it "inserts rows into the configured spans table" do
      client = described_class.new(config: config)
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(client).to receive(:post_query).and_return(response)

      client.insert_span!({ span_id: "abc123" })

      expect(client).to have_received(:post_query).with(/INSERT INTO logister\.spans FORMAT JSONEachRow/, "{\"span_id\":\"abc123\"}\n")
    end
  end

  describe "#select_rows!" do
    it "returns JSONEachRow query rows" do
      client = described_class.new(config: config)
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return(%({"bucket":"2026-05-21 12:00:00","count":2}\n{"bucket":"2026-05-21 12:01:00","count":3}\n))
      allow(client).to receive(:post_query).and_return(response)

      rows = client.select_rows!("SELECT bucket, count FROM logister.events_1m")

      expect(rows).to eq(
        [
          { "bucket" => "2026-05-21 12:00:00", "count" => 2 },
          { "bucket" => "2026-05-21 12:01:00", "count" => 3 }
        ]
      )
      expect(client).to have_received(:post_query).with(/FORMAT JSONEachRow\z/, "")
    end

    it "raises when ClickHouse returns a non-success response" do
      client = described_class.new(config: config)
      response = instance_double(Net::HTTPResponse, code: "500", body: "nope")
      allow(client).to receive(:post_query).and_return(response)

      expect {
        client.select_rows!("SELECT 1")
      }.to raise_error(Logister::ClickhouseClient::Error, /500 nope/)
    end
  end

  describe "#execute!" do
    it "runs raw ClickHouse statements without appending a JSONEachRow format" do
      client = described_class.new(config: config)
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return("created")
      allow(client).to receive(:post_query).and_return(response)

      expect(client.execute!("CREATE TABLE logister.events")).to eq("created")

      expect(client).to have_received(:post_query).with("CREATE TABLE logister.events", "")
    end
  end

  describe "#load_schema!" do
    it "splits and executes schema statements" do
      client = described_class.new(config: config)
      allow(client).to receive(:execute!)

      count = client.load_schema!("CREATE DATABASE logister;\nCREATE TABLE logister.events;\n")

      expect(count).to eq(2)
      expect(client).to have_received(:execute!).with("CREATE DATABASE logister")
      expect(client).to have_received(:execute!).with("CREATE TABLE logister.events")
    end
  end

  describe "#healthy?" do
    let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(cache_store)
      cache_store.clear
    end

    it "caches the health probe result briefly" do
      client = described_class.new(config: config)
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return("1")
      allow(client).to receive(:post_query).and_return(response)

      2.times { expect(client.healthy?).to be(true) }

      expect(client).to have_received(:post_query).once
    end

    it "returns false when the health query raises" do
      client = described_class.new(config: config)
      allow(client).to receive(:post_query).and_raise(StandardError, "timeout")

      expect(client.healthy?).to be(false)
    end
  end

  describe "#schema_status" do
    let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(cache_store)
      cache_store.clear
    end

    it "reports missing ClickHouse tables" do
      client = described_class.new(config: config)
      allow(client).to receive(:healthy?).and_return(true)
      allow(client).to receive(:select_rows!).and_return([
        { "name" => "events" },
        { "name" => "events_1m" },
        { "name" => "mv_events_1m" }
      ])

      status = client.schema_status

      expect(status).to include(
        enabled: true,
        healthy: true,
        ready: false,
        database: "logister"
      )
      expect(status[:missing_tables]).to include("spans")
    end
  end
end
