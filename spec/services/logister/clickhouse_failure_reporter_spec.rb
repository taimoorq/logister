# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseFailureReporter do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:error) { Logister::ClickhouseClient::Error.new("insert failed") }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    cache_store.clear
    allow(Logister).to receive(:report_log)
    allow(Logister).to receive(:report_metric)
  end

  def reporter
    described_class.new(
      kind: "event",
      subject_key: :ingest_event_id,
      subject_id: 123,
      error: error,
      log_message: "ClickHouse ingest failed",
      log_fingerprint: "logister:clickhouse_ingest:failure",
      metric_name: "logister.clickhouse.ingest_failure",
      metric_fingerprint: "logister:metric:clickhouse_ingest_failure"
    )
  end

  it "reports the first failure for a signature" do
    expect(reporter.call).to be(true)

    expect(Logister).to have_received(:report_log).with(
      hash_including(
        message: "ClickHouse ingest failed",
        context: hash_including(
          clickhouse_ingest: hash_including(ingest_event_id: 123),
          throttle: hash_including(window_seconds: 60)
        )
      )
    )
    expect(Logister).to have_received(:report_metric).with(
      hash_including(message: "logister.clickhouse.ingest_failure")
    )
  end

  it "throttles duplicate failures for the same signature" do
    expect(reporter.call).to be(true)
    expect(reporter.call).to be(false)

    expect(Logister).to have_received(:report_log).once
    expect(Logister).to have_received(:report_metric).once
  end
end
