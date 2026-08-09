# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseSchemaRepairer do
  let(:schema_sql) do
    <<~SQL
      CREATE DATABASE IF NOT EXISTS logister;
      CREATE TABLE IF NOT EXISTS logister.events_raw (event_type String);
      CREATE TABLE IF NOT EXISTS logister.spans_raw (span_id UUID);
      CREATE TABLE IF NOT EXISTS logister.events_1m (event_type String);
    SQL
  end
  let(:client) do
    instance_double(
      Logister::ClickhouseClient,
      enabled?: true,
      database_name: "analytics",
      events_table: "custom_events",
      events_table_name: "analytics.custom_events",
      spans_table_name: "analytics.custom_spans"
    )
  end

  before do
    allow(client).to receive(:qualified_table_name) { |name| "analytics.#{name}" }
    allow(client).to receive(:load_schema!).and_return(4)
    allow(client).to receive(:execute!)
    allow(client).to receive(:clear_schema_cache!)
    allow(client).to receive(:schema_status).and_return(ready: true, schema_issues: [], missing_tables: [])
  end

  it "renders configured identifiers and leaves a canonical schema unchanged" do
    allow(client).to receive(:event_type_column_types).and_return(
      "custom_events" => Logister::ClickhouseClient::CANONICAL_EVENT_TYPE,
      "events_1m" => Logister::ClickhouseClient::CANONICAL_EVENT_TYPE,
      "mv_events_1m" => Logister::ClickhouseClient::CANONICAL_EVENT_TYPE
    )

    result = described_class.call(client: client, schema_sql: schema_sql)

    expect(client).to have_received(:load_schema!).with(a_string_including(
      "CREATE DATABASE IF NOT EXISTS analytics",
      "analytics.custom_events",
      "analytics.custom_spans",
      "analytics.events_1m"
    ))
    expect(client).to have_received(:execute!).with(
      "ALTER TABLE analytics.custom_events MODIFY SETTING non_replicated_deduplication_window = 10000"
    )
    expect(client).to have_received(:execute!).with(
      "ALTER TABLE analytics.custom_spans MODIFY SETTING non_replicated_deduplication_window = 10000"
    )
    expect(result).to include(
      repaired_columns: [],
      rebuilt_views: [],
      deduplication_tables: %w[analytics.custom_events analytics.custom_spans]
    )
  end

  it "repairs the raw event enum without recreating unsafe materialized rollups" do
    old_type = "Enum8('error' = 1, 'metric' = 2)"
    allow(client).to receive(:event_type_column_types).and_return(
      "custom_events" => old_type,
      "events_1m" => old_type,
      "mv_events_1m" => old_type
    )
    result = described_class.call(client: client, schema_sql: schema_sql)

    expect(client).to have_received(:execute!).with(
      "ALTER TABLE analytics.custom_events MODIFY COLUMN event_type #{Logister::ClickhouseClient::CANONICAL_EVENT_TYPE}"
    ).ordered
    expect(client).to have_received(:execute!).with(
      "ALTER TABLE analytics.custom_events MODIFY SETTING non_replicated_deduplication_window = 10000"
    ).ordered
    expect(client).to have_received(:execute!).with(
      "ALTER TABLE analytics.custom_spans MODIFY SETTING non_replicated_deduplication_window = 10000"
    ).ordered
    expect(result).to include(
      repaired_columns: %w[custom_events],
      rebuilt_views: [],
      deduplication_tables: %w[analytics.custom_events analytics.custom_spans]
    )
  end

  it "fails instead of accepting a partially repaired schema" do
    allow(client).to receive(:event_type_column_types).and_return({})
    allow(client).to receive(:schema_status).and_return(
      ready: false,
      schema_issues: [ "events_1m.event_type is missing" ],
      missing_tables: []
    )

    expect {
      described_class.call(client: client, schema_sql: schema_sql)
    }.to raise_error(Logister::ClickhouseClient::Error, /repair incomplete.*event_type is missing/)
  end

  it "skips all schema work when ClickHouse is disabled" do
    disabled_client = instance_double(
      Logister::ClickhouseClient,
      enabled?: false,
      schema_status: { enabled: false, ready: false }
    )

    result = described_class.call(client: disabled_client, schema_sql: schema_sql)

    expect(result).to include(enabled: false, loaded_statements: 0)
  end
end
