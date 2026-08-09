# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseSpanBackfill, type: :model do
  let(:watermark_result) { double(status: "verified") }
  let(:watermark_reconciler) do
    class_double(Logister::ClickhouseBackfillWatermarkReconciler, call: watermark_result)
  end

  it "copies retained spans in bounded batches and verifies every requested hour" do
    project = create(:project)
    spans = create_list(:trace_span, 3, project: project, started_at: Time.utc(2026, 8, 8, 10, 15))
    client = instance_double(
      Logister::ClickhouseClient,
      enabled?: true,
      spans_table_name: "logister.spans_raw"
    )
    allow(client).to receive(:select_rows!).and_return([])
    allow(client).to receive(:insert_spans!)
    backfill = described_class.new(
      scope: TraceSpan.where(id: spans.map(&:id)),
      client: client,
      batch_size: 2,
      coverage_from: Time.utc(2026, 8, 8, 10),
      coverage_to: Time.utc(2026, 8, 8, 12),
      project_ids: [ project.id ],
      source_complete: true,
      watermark_reconciler: watermark_reconciler
    )

    inserted = backfill.call

    expect(inserted).to eq(3)
    expect(client).to have_received(:insert_spans!).twice
    expect(watermark_reconciler).to have_received(:call).twice
    expect(backfill.watermark_results.length).to eq(2)
  end

  it "skips only the same project's current checksum and projection version" do
    span = create(:trace_span)
    client = instance_double(
      Logister::ClickhouseClient,
      enabled?: true,
      spans_table_name: "logister.spans_raw"
    )
    allow(client).to receive(:select_rows!).and_return(
      [ { "project_id" => span.project_id, "span_id" => span.uuid } ]
    )
    allow(client).to receive(:insert_spans!)

    inserted = described_class.new(
      scope: TraceSpan.where(id: span.id),
      client: client,
      source_complete: true,
      watermark_reconciler: watermark_reconciler
    ).call

    expect(inserted).to eq(0)
    expect(client).not_to have_received(:insert_spans!)
    expect(client).to have_received(:select_rows!).with(
      a_string_including(
        "(project_id, span_id, identity_checksum, projection_version) IN",
        "toUUID('#{span.uuid}')",
        "toUInt128('#{span.uuid.delete('-').to_i(16)}')"
      )
    )
  end
end
