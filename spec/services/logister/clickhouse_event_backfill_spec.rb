# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseEventBackfill, type: :model do
  let(:watermark_result) { double(status: "verified") }
  let(:watermark_reconciler) do
    class_double(Logister::ClickhouseBackfillWatermarkReconciler, call: watermark_result)
  end

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
      batch_size: 2,
      source_complete: true,
      watermark_reconciler: watermark_reconciler
    ).call

    expect(inserted).to eq(3)
    expect(client).to have_received(:insert_events!).twice
  end

  it "skips only the same project's fully projected event version so reruns are safe" do
    events = create_list(:ingest_event, 2, :log)
    client = instance_double(
      Logister::ClickhouseClient,
      enabled?: true,
      events_table_name: "logister.events_raw"
    )
    allow(client).to receive(:select_rows!).and_return(
      [ { "project_id" => events.first.project_id, "event_id" => events.first.uuid } ]
    )
    allow(client).to receive(:insert_events!)

    inserted = described_class.new(
      scope: IngestEvent.where(id: events.map(&:id)),
      client:,
      source_complete: true,
      watermark_reconciler: watermark_reconciler
    ).call

    expect(inserted).to eq(1)
    expect(client).to have_received(:insert_events!).with(
      contain_exactly(hash_including(event_id: events.second.uuid))
    )
    expect(client).to have_received(:select_rows!).with(
      a_string_including(
        "(project_id, event_id, identity_checksum, projection_version) IN",
        events.first.project_id.to_s,
        "toUUID('#{events.first.uuid}')",
        "toUInt128('#{events.first.uuid.delete('-').to_i(16)}')"
      )
    )
  end

  it "reprojects a legacy v1 identity instead of treating its zero checksum/version as current" do
    event = create(:ingest_event, :log)
    client = instance_double(
      Logister::ClickhouseClient,
      enabled?: true,
      events_table_name: "logister.events_raw"
    )
    allow(client).to receive(:select_rows!).and_return([])
    allow(client).to receive(:insert_events!)

    inserted = described_class.new(
      scope: IngestEvent.where(id: event.id),
      client: client,
      source_complete: true,
      watermark_reconciler: watermark_reconciler
    ).call

    expect(inserted).to eq(1)
    expect(client).to have_received(:insert_events!).with(
      contain_exactly(hash_including(
        event_id: event.uuid,
        identity_checksum: event.uuid.delete("-").to_i(16),
        projection_version: be > 1
      ))
    )
  end

  it "requests explicit zero/nonzero watermark evidence for every event signal and hour" do
    project = create(:project)
    event = create(:ingest_event, :log, project: project, occurred_at: Time.utc(2026, 8, 8, 10, 15))
    client = instance_double(
      Logister::ClickhouseClient,
      enabled?: true,
      events_table_name: "logister.events_raw"
    )
    allow(client).to receive(:select_rows!).and_return([])
    allow(client).to receive(:insert_events!)

    backfill = described_class.new(
      scope: IngestEvent.where(id: event.id),
      client: client,
      coverage_from: Time.utc(2026, 8, 8, 10, 30),
      coverage_to: Time.utc(2026, 8, 8, 12),
      project_ids: [ project.id ],
      source_complete: true,
      watermark_reconciler: watermark_reconciler
    )
    backfill.call

    expect(watermark_reconciler).to have_received(:call).exactly(10).times
    expect(watermark_reconciler).to have_received(:call).with(
      client: client,
      project_id: project.id,
      signal: "metric",
      bucket_start_at: Time.utc(2026, 8, 8, 11),
      source_complete: true
    )
    expect(backfill.watermark_results.length).to eq(10)
  end
end
