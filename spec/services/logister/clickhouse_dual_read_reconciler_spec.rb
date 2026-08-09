# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseDualReadReconciler do
  it "compares equivalent normalized query mappings without a live ClickHouse server" do
    reconciler = described_class.new(sample_rate: 1.0, logger: instance_double(Logger, warn: nil))
    postgres = {
      summary: { events: 3, latest_event_at: "2026-08-08T11:00:00Z" },
      standard_bucket_rows: [ { "bucket_time" => "2026-08-08T11:00:00Z", "events_total" => 3 } ]
    }
    clickhouse = postgres.deep_dup

    result = reconciler.compare(primary: clickhouse, shadow: postgres, context: { capability: "insights" })

    expect(result).to be_compared
    expect(result.equivalent).to be(true)
    expect(result.primary_digest).to eq(result.shadow_digest)
  end

  it "reports a logical mismatch" do
    logger = instance_double(Logger, warn: nil)
    reconciler = described_class.new(sample_rate: 1.0, logger: logger)

    result = reconciler.compare(primary: { events: 4 }, shadow: { events: 3 })

    expect(result.equivalent).to be(false)
    expect(logger).to have_received(:warn).with(/dual-read mismatch/)
  end
end
