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
end
