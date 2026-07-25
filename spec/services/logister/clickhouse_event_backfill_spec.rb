# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseEventBackfill, type: :model do
  it "copies events to ClickHouse in bounded batches" do
    events = create_list(:ingest_event, 3, :log)
    client = instance_double(
      Logister::ClickhouseClient,
      enabled?: true,
      events_table_name: "logister.events_raw"
    )
    allow(client).to receive(:select_rows!).and_return([])
    allow(client).to receive(:insert_events!)

    inserted = described_class.new(
      scope: IngestEvent.where(id: events.map(&:id)),
      client:,
      batch_size: 2
    ).call

    expect(inserted).to eq(3)
    expect(client).to have_received(:insert_events!).twice
  end

  it "skips event IDs that are already present so reruns are safe" do
    events = create_list(:ingest_event, 2, :log)
    client = instance_double(
      Logister::ClickhouseClient,
      enabled?: true,
      events_table_name: "logister.events_raw"
    )
    allow(client).to receive(:select_rows!).and_return([ { "event_id" => events.first.uuid } ])
    allow(client).to receive(:insert_events!)

    inserted = described_class.new(scope: IngestEvent.where(id: events.map(&:id)), client:).call

    expect(inserted).to eq(1)
    expect(client).to have_received(:insert_events!).with(
      contain_exactly(hash_including(event_id: events.second.uuid))
    )
  end
end
