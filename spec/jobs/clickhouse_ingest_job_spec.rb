# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClickhouseIngestJob, type: :job do
  include ActiveJob::TestHelper

  it "enqueues with default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "calls EventIngestor with event and request_context" do
    event = ingest_events(:one)
    request_context = { "ip" => "1.2.3.4", "user_agent" => "Test" }
    ingestor = instance_double(Logister::EventIngestor, call: nil)
    allow(Logister::EventIngestor).to receive(:new).with(
      event: event,
      request_context: { ip: "1.2.3.4", user_agent: "Test" }
    ).and_return(ingestor)

    perform_enqueued_jobs do
      described_class.perform_later(event.id, request_context)
    end

    expect(ingestor).to have_received(:call)
  end

  it "discards when IngestEvent is not found" do
    expect {
      perform_enqueued_jobs do
        described_class.perform_later(999_999)
      end
    }.not_to raise_error
  end

  it "reports ClickHouse ingest failures through Logister" do
    event = ingest_events(:one)
    ingestor = instance_double(Logister::EventIngestor)
    allow(Logister::EventIngestor).to receive(:new).and_return(ingestor)
    allow(ingestor).to receive(:call).and_raise(Logister::ClickhouseClient::Error, "insert failed")
    allow(Logister).to receive(:report_log)
    allow(Logister).to receive(:report_metric)

    described_class.perform_now(event.id)

    expect(Logister).to have_received(:report_log).with(
      hash_including(
        message: "ClickHouse ingest failed",
        level: "error",
        fingerprint: "logister:clickhouse_ingest:failure",
        context: hash_including(
          clickhouse_ingest: hash_including(ingest_event_id: event.id)
        )
      )
    )
    expect(Logister).to have_received(:report_metric).with(
      hash_including(
        message: "logister.clickhouse.ingest_failure",
        level: "error",
        context: hash_including(
          metric: hash_including(name: "logister.clickhouse.ingest_failure", value: 1, unit: "count")
        )
      )
    )
  end
end
