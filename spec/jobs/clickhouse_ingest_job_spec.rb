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
end
