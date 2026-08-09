# frozen_string_literal: true

require "spec_helper"
require_relative "../../../config/environment"

RSpec.describe "Project purge external adapters" do
  FakePurge = Struct.new(:source_project_id, :project_uuid, :configuration_snapshot, keyword_init: true)

  class FakePurgeCache
    attr_reader :patterns

    def initialize(keys)
      @keys = keys
      @patterns = []
    end

    def delete_matched(pattern)
      @patterns << pattern
      expression = Regexp.new("\\A#{Regexp.escape(pattern).gsub('\\*', '.*')}\\z")
      matched = @keys.grep(expression)
      @keys -= matched
      matched.size
    end
  end

  class FakePurgeClickhouseClient
    attr_reader :executed
    attr_accessor :closed

    def initialize
      @executed = []
      @closed = false
    end

    def enabled? = true
    def database_name = "logister"
    def events_table = "events_raw"
    def spans_table = "spans_raw"
    def qualified_table_name(table) = "logister.#{table}"
    def close = self.closed = true

    def execute!(query)
      @executed << query
    end

    def select_rows!(query)
      if query.include?("system.tables")
        %w[events_raw spans_raw events_1m request_spans_1m].map { |name| { "name" => name } }
      else
        [ { "count" => "0" } ]
      end
    end
  end

  describe Logister::ProjectPurgeAdapters::RedisDerived do
    it "clears and rechecks project namespaces without touching Sidekiq Redis" do
      purge = FakePurge.new(source_project_id: 42, project_uuid: "project-uuid", configuration_snapshot: {})
      cache = FakePurgeCache.new([
        "project/42/inbox",
        "project/project-uuid/insights",
        "project/7/inbox"
      ])

      result = described_class.new(project_purge: purge, cache: cache).call

      expect(result).to include(
        status: "completed",
        direct_project_namespaces_verified_absent: true,
        sidekiq_redis_touched: false
      )
      expect(cache.patterns).to eq([
        "project/42/*",
        "project/project-uuid/*",
        "project/42/*",
        "project/project-uuid/*"
      ])
    end
  end

  describe Logister::ProjectPurgeAdapters::Clickhouse do
    let(:snapshot) do
      {
        "clickhouse" => {
          "mode" => "dual_write",
          "database" => "logister",
          "events_table" => "events_raw",
          "spans_table" => Rails.configuration.x.logister.clickhouse_spans_table,
          "generation_inventory_complete" => true,
          "generations" => [
            {
              "generation_id" => "generation-1",
              "url" => "http://clickhouse.example.test:8123",
              "database" => "logister",
              "events_table" => "events_raw",
              "spans_table" => "spans_raw",
              "username" => "default"
            }
          ]
        }
      }
    end

    it "keeps cross-store deletion behind an explicit rollout gate" do
      purge = FakePurge.new(source_project_id: 42, project_uuid: "project-uuid", configuration_snapshot: snapshot)
      client = FakePurgeClickhouseClient.new

      result = described_class.new(project_purge: purge, client: client, enabled: false).call

      expect(result).to include(status: "awaiting_external", rollout_gate: "LOGISTER_ENABLE_PROJECT_PURGE_CLICKHOUSE")
      expect(client.executed).to be_empty
      expect(client.closed).to be(false)
    end

    it "synchronously mutates raw facts and rollups and verifies zero remaining rows" do
      purge = FakePurge.new(source_project_id: 42, project_uuid: "project-uuid", configuration_snapshot: snapshot)
      client = FakePurgeClickhouseClient.new

      result = described_class.new(project_purge: purge, client: client, enabled: true).call

      expect(result).to include(status: "completed", verified_absent: true)
      expect(result.fetch(:generations).sole.fetch(:mutated_tables)).to contain_exactly(
        "events_raw",
        "spans_raw",
        "events_1m",
        "request_spans_1m"
      )
      expect(client.executed).to all(include("project_id = 42", "mutations_sync = 2"))
      expect(client.closed).to be(false)
    end

    it "does not treat disabled mode as proof that ClickHouse was never used" do
      unsafe_snapshot = { "clickhouse" => { "mode" => "disabled", "generations" => [] } }
      purge = FakePurge.new(source_project_id: 42, project_uuid: "project-uuid", configuration_snapshot: unsafe_snapshot)

      result = described_class.new(project_purge: purge, client: FakePurgeClickhouseClient.new, enabled: true).call

      expect(result).to include(status: "awaiting_external", verified_absent: false)
      expect(result.fetch(:reason)).to match(/generation.*inventory/)
    end

    it "does not construct an owned ClickHouse client before an early gate passes" do
      purge = FakePurge.new(source_project_id: 42, project_uuid: "project-uuid", configuration_snapshot: snapshot)
      client = FakePurgeClickhouseClient.new
      allow(Logister::ClickhouseClient).to receive(:new).and_return(client)

      result = described_class.new(project_purge: purge, enabled: false).call

      expect(result).to include(status: "awaiting_external")
      expect(Logister::ClickhouseClient).not_to have_received(:new)
      expect(client.closed).to be(false)
    end
  end
end
