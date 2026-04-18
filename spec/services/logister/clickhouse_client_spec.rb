# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe Logister::ClickhouseClient do
  describe "#healthy?" do
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
  end
end
