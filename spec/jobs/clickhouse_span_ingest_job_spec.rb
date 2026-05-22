# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClickhouseSpanIngestJob, type: :job do
  include ActiveJob::TestHelper

  it "enqueues with default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "calls SpanIngestor with span and request_context" do
    span = create(:trace_span)
    request_context = { "ip" => "1.2.3.4", "user_agent" => "Test" }
    ingestor = instance_double(Logister::SpanIngestor, call: nil)
    allow(Logister::SpanIngestor).to receive(:new).with(
      span: span,
      request_context: { ip: "1.2.3.4", user_agent: "Test" }
    ).and_return(ingestor)

    perform_enqueued_jobs do
      described_class.perform_later(span.id, request_context)
    end

    expect(ingestor).to have_received(:call)
  end

  it "discards when TraceSpan is not found" do
    expect {
      perform_enqueued_jobs do
        described_class.perform_later(999_999)
      end
    }.not_to raise_error
  end

  it "reports ClickHouse span ingest failures through logister-ruby" do
    span = create(:trace_span)
    ingestor = instance_double(Logister::SpanIngestor)
    allow(Logister::SpanIngestor).to receive(:new).and_return(ingestor)
    allow(ingestor).to receive(:call).and_raise(Logister::ClickhouseClient::Error, "insert failed")
    allow(Logister).to receive(:report_log)
    allow(Logister).to receive(:report_metric)

    described_class.perform_now(span.id)

    expect(Logister).to have_received(:report_log).with(
      hash_including(
        message: "ClickHouse span ingest failed",
        level: "error",
        fingerprint: "logister:clickhouse_span_ingest:failure",
        context: hash_including(
          clickhouse_ingest: hash_including(trace_span_id: span.id)
        )
      )
    )
    expect(Logister).to have_received(:report_metric).with(
      hash_including(
        message: "logister.clickhouse.span_ingest_failure",
        level: "error",
        context: hash_including(
          metric: hash_including(name: "logister.clickhouse.span_ingest_failure", value: 1, unit: "count")
        )
      )
    )
  end
end
