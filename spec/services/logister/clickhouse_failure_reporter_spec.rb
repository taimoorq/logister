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

  it "uses the event failure preset helper" do
    expect(described_class.report_event_failure(456, error)).to be(true)

    expect(Logister).to have_received(:report_log).with(
      hash_including(
        message: "ClickHouse ingest failed",
        context: hash_including(clickhouse_ingest: hash_including(ingest_event_id: 456))
      )
    )
    expect(Logister).to have_received(:report_metric).with(
      hash_including(message: "logister.clickhouse.ingest_failure")
    )
  end

  it "uses the span failure preset helper" do
    expect(described_class.report_span_failure(789, error)).to be(true)

    expect(Logister).to have_received(:report_log).with(
      hash_including(
        message: "ClickHouse span ingest failed",
        context: hash_including(clickhouse_ingest: hash_including(trace_span_id: 789))
      )
    )
    expect(Logister).to have_received(:report_metric).with(
      hash_including(message: "logister.clickhouse.span_ingest_failure")
    )
  end

  it "reports when cache throttling fails open" do
    allow(cache_store).to receive(:write).and_raise(StandardError, "cache unavailable")

    expect(reporter.call).to be(true)

    expect(Logister).to have_received(:report_log)
    expect(Logister).to have_received(:report_metric)
  end

  it "clamps invalid throttle values to at least one second" do
    previous_value = ENV["LOGISTER_CLICKHOUSE_FAILURE_THROTTLE_SECONDS"]
    ENV["LOGISTER_CLICKHOUSE_FAILURE_THROTTLE_SECONDS"] = "0"

    expect(reporter.call).to be(true)

    expect(Logister).to have_received(:report_log).with(
      hash_including(context: hash_including(throttle: hash_including(window_seconds: 1)))
    )
  ensure
    ENV["LOGISTER_CLICKHOUSE_FAILURE_THROTTLE_SECONDS"] = previous_value
  end
end
