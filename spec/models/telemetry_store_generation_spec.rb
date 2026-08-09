# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe TelemetryStoreGeneration, type: :model do
  def clickhouse_config(password: "first-secret")
    OpenStruct.new(
      clickhouse_mode: "dual_write",
      clickhouse_url: "https://embedded:credential@clickhouse.example.test:8443",
      clickhouse_database: "logister",
      clickhouse_events_table: "events_raw",
      clickhouse_spans_table: "spans_raw",
      clickhouse_username: "logister",
      clickhouse_password: password
    )
  end

  it "records a non-secret, deterministic ClickHouse store generation" do
    first = described_class.register_clickhouse!(clickhouse_config)
    second = described_class.register_clickhouse!(clickhouse_config(password: "rotated-secret"))

    expect(second.id).to eq(first.id)
    expect(first.locator.fetch("url")).to eq("https://clickhouse.example.test:8443")
    expect(first.locator.to_json).not_to include("credential", "first-secret", "rotated-secret")
    expect(first.generation_id).to eq(described_class.generation_id_for(first.locator))
  end

  it "does not register a disabled store as historically used" do
    config = clickhouse_config
    config.clickhouse_mode = "disabled"

    expect(described_class.register_clickhouse!(config)).to be_nil
    expect(described_class.where(store_kind: "clickhouse")).to be_empty
  end
end
