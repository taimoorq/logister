# frozen_string_literal: true

require "rails_helper"
require "ostruct"
require "zlib"

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

    it "normalizes transport failures for optional ingest handling" do
      client = described_class.new(config: config)
      allow(client).to receive(:with_http_connection).and_raise(Net::OpenTimeout, "connection timed out")

      expect {
        client.insert_event!({ event_id: "abc123" })
      }.to raise_error(Logister::ClickhouseClient::Error, /Net::OpenTimeout: connection timed out/)
    end

    it "opens the circuit after a real transport failure without a ClickHouse server" do
      unavailable_config = config.dup
      unavailable_config.clickhouse_url = "http://127.0.0.1:1"
      unavailable_config.clickhouse_circuit_failure_threshold = 1
      unavailable_config.clickhouse_circuit_open_seconds = 30
      cache = ActiveSupport::Cache::MemoryStore.new
      breaker = Logister::ClickhouseCircuitBreaker.new(config: unavailable_config, cache: cache)
      client = described_class.new(config: unavailable_config, circuit_breaker: breaker)

      expect { client.insert_event!({ event_id: "first" }) }
        .to raise_error(Logister::ClickhouseClient::Error, /request failed/)
      expect { client.insert_event!({ event_id: "second" }) }
        .to raise_error(Logister::ClickhouseClient::CircuitOpen, /circuit breaker is open/)
      expect(client.circuit_breaker_status).to include("state" => "open")
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

    it "rejects unsafe ClickHouse table identifiers before sending a request" do
      unsafe_config = config.dup
      unsafe_config.clickhouse_events_table = "events;DROP TABLE users"
      client = described_class.new(config: unsafe_config)
      expect(client).not_to receive(:post_query)

      expect {
        client.insert_event!({ event_id: "abc123" })
      }.to raise_error(Logister::ClickhouseClient::Error, /Unsafe ClickHouse identifier/)
    end

    it "rejects unsafe ClickHouse database identifiers before sending a request" do
      unsafe_config = config.dup
      unsafe_config.clickhouse_database = "logister-prod"
      client = described_class.new(config: unsafe_config)
      expect(client).not_to receive(:post_query)

      expect {
        client.insert_event!({ event_id: "abc123" })
      }.to raise_error(Logister::ClickhouseClient::Error, /Unsafe ClickHouse identifier/)
    end

    it "inserts event batches in one JSONEachRow request" do
      client = described_class.new(config: config)
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(client).to receive(:post_query).and_return(response)

      client.insert_events!([ { event_id: "one" }, { event_id: "two" } ])

      expect(client).to have_received(:post_query).with(
        /INSERT INTO logister\.events FORMAT JSONEachRow/,
        "{\"event_id\":\"one\"}\n{\"event_id\":\"two\"}\n"
      )
    end

    it "compresses projector batches and sends deterministic ClickHouse deduplication settings" do
      breaker = instance_double(
        Logister::ClickhouseCircuitBreaker,
        allow_request?: true,
        record_success!: true,
        record_failure!: true,
        status: { "state" => "closed" }
      )
      client = described_class.new(config: config, circuit_breaker: breaker)
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      http = instance_double(Net::HTTP)
      captured_request = nil
      allow(http).to receive(:request) do |request|
        captured_request = request
        response
      end
      allow(client).to receive(:with_http_connection).and_yield(http)

      client.insert_events!(
        [ { event_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" } ],
        deduplication_token: "logister-v1-batch",
        gzip: true
      )

      params = URI.decode_www_form(captured_request.uri.query).to_h
      expect(params).to include(
        "insert_deduplication_token" => "logister-v1-batch",
        "insert_deduplicate" => "1",
        "deduplicate_blocks_in_dependent_materialized_views" => "1"
      )
      expect(captured_request["Content-Encoding"]).to eq("gzip")
      expect(Zlib::GzipReader.new(StringIO.new(captured_request.body)).read).to eq(
        "{\"event_id\":\"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\"}\n"
      )
    end

    it "classifies client response errors as terminal and server responses as retryable" do
      expect(described_class::ResponseError.new("bad row", status_code: 400)).not_to be_retryable
      expect(described_class::ResponseError.new("busy", status_code: 503)).to be_retryable
      expect(described_class::ResponseError.new("limited", status_code: 429)).to be_retryable
    end
  end

  describe "activation modes" do
    it "writes but does not read in dual-write mode" do
      config.clickhouse_mode = "dual_write"
      client = described_class.new(config: config)

      expect(client).to be_write_enabled
      expect(client).not_to be_read_enabled
    end

    it "allows analytics reads only in read-preferred mode" do
      config.clickhouse_mode = "read_preferred"
      client = described_class.new(config: config)

      expect(client).to be_write_enabled
      expect(client).to be_read_enabled
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

    it "returns an empty result when ClickHouse is disabled" do
      disabled_config = config.dup
      disabled_config.clickhouse_enabled = false
      client = described_class.new(config: disabled_config)

      expect(client.execute!("SELECT 1")).to eq("")
    end
  end

  describe "#build_uri" do
    it "preserves existing endpoint query parameters" do
      query_config = config.dup
      query_config.clickhouse_url = "https://clickhouse.example.com/?session_id=abc"
      client = described_class.new(config: query_config)

      params = URI.decode_www_form(client.send(:build_uri, "SELECT 1").query)

      expect(params).to include([ "session_id", "abc" ], [ "query", "SELECT 1" ])
    end
  end

  describe "persistent HTTP connections" do
    it "reuses a started connection for the same endpoint" do
      client = described_class.new(config: config)
      http = instance_double(Net::HTTP, active?: true, start: true, finish: true)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:keep_alive_timeout=)
      allow(Net::HTTP).to receive(:new).and_return(http)
      uri = URI.parse(config.clickhouse_url)

      2.times { client.send(:with_http_connection, uri) { |connection| expect(connection).to be(http) } }

      expect(Net::HTTP).to have_received(:new).once
      client.close
      expect(http).to have_received(:finish).once
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
      allow(client).to receive(:select_rows!).and_return(
        [
          { "name" => "events" },
          { "name" => "events_1m" },
          { "name" => "mv_events_1m" }
        ],
        []
      )

      status = client.schema_status

      expect(status).to include(
        enabled: true,
        healthy: true,
        ready: false,
        database: "logister"
      )
      expect(status[:missing_tables]).to include("spans")
    end

    it "reports event type enum drift even when all objects exist" do
      client = described_class.new(config: config)
      allow(client).to receive(:healthy?).and_return(true)
      objects = described_class::REQUIRED_TABLES.map do |name|
        configured_name = { "events_raw" => "events", "spans_raw" => "spans" }.fetch(name, name)
        { "name" => configured_name, "engine" => name.in?(%w[events_raw spans_raw]) ? "MergeTree" : "View" }
      end
      event_types = %w[events event_facts_v2 event_facts_1m_v2 event_facts_1h_v2].map do |name|
        {
          "table" => name,
          "type" => name == "events" ? "Enum8('error' = 1, 'metric' = 2)" : described_class::CANONICAL_EVENT_TYPE
        }
      end
      raw_columns = described_class::REQUIRED_RAW_COLUMNS.flat_map do |generic_table, columns|
        table = { "events_raw" => "events", "spans_raw" => "spans" }.fetch(generic_table)
        columns.map { |name, type| { "table" => table, "name" => name, "type" => type } }
      end
      allow(client).to receive(:select_rows!).and_return(
        objects,
        event_types,
        raw_columns
      )

      status = client.schema_status

      expect(status).to include(healthy: true, ready: false, missing_tables: [])
      expect(status[:schema_issues]).to contain_exactly(/events\.event_type uses Enum8/)
    end

    it "reports disabled status without probing ClickHouse" do
      disabled_config = config.dup
      disabled_config.clickhouse_enabled = false
      client = described_class.new(config: disabled_config)
      expect(client).not_to receive(:post_query)

      expect(client.schema_status).to include(
        enabled: false,
        healthy: false,
        ready: false,
        missing_tables: [],
        schema_issues: []
      )
    end
  end
end
