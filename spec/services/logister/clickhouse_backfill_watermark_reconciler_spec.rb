# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseBackfillWatermarkReconciler, type: :model do
  let(:bucket) { Time.utc(2026, 8, 8, 10) }
  let(:project) { create(:project) }
  let(:client) do
    instance_double(
      Logister::ClickhouseClient,
      event_facts_table_name: "logister.event_facts_v2",
      span_facts_table_name: "logister.span_facts_v2"
    )
  end

  it "publishes an idempotent absolute event watermark after count and checksum match" do
    event = create(:ingest_event, :metric, project: project, occurred_at: bucket + 5.minutes)
    checksum = event.uuid.delete("-").to_i(16)
    allow(client).to receive(:select_rows!).and_return(
      [ { "logical_count" => 1, "checksum" => checksum.to_s } ]
    )

    2.times do
      result = described_class.call(
        client: client,
        project_id: project.id,
        signal: "metric",
        bucket_start_at: bucket,
        source_complete: true
      )
      expect(result).to be_verified
    end

    watermark = TelemetryProjectionWatermark.find_by!(
      project: project,
      signal: "metric",
      destination: "clickhouse_event",
      bucket_start_at: bucket
    )
    expect(watermark).to be_complete
    expect(watermark).to have_attributes(
      accepted_count: 1,
      delivered_count: 1,
      accepted_checksum: checksum,
      delivered_checksum: checksum
    )
  end

  it "refuses to certify matching retained stores without a complete-source baseline" do
    event = create(:ingest_event, :metric, project: project, occurred_at: bucket + 5.minutes)
    checksum = event.uuid.delete("-").to_i(16)
    allow(client).to receive(:select_rows!).and_return(
      [ { "logical_count" => 1, "checksum" => checksum.to_s } ]
    )

    result = described_class.call(
      client: client,
      project_id: project.id,
      signal: "metric",
      bucket_start_at: bucket
    )

    expect(result.status).to eq("source_baseline_required")
    expect(TelemetryProjectionWatermark.find_by!(project: project, signal: "metric")).not_to be_complete
  end

  it "persists a durable zero seal for a verified empty project/signal/hour" do
    allow(client).to receive(:select_rows!).and_return(
      [ { "logical_count" => 0, "checksum" => "0" } ]
    )

    result = described_class.call(
      client: client,
      project_id: project.id,
      signal: "log",
      bucket_start_at: bucket,
      source_complete: true
    )

    expect(result).to be_verified
    watermark = TelemetryProjectionWatermark.find_by!(project: project, signal: "log", bucket_start_at: bucket)
    expect(watermark).to be_complete
    expect(watermark).to have_attributes(accepted_count: 0, delivered_count: 0)
  end

  it "stores absolute mismatch evidence and refuses to mark the bucket complete" do
    event = create(:ingest_event, :log, project: project, occurred_at: bucket + 5.minutes)
    allow(client).to receive(:select_rows!).and_return(
      [ { "logical_count" => 0, "checksum" => "0" } ]
    )

    result = described_class.call(
      client: client,
      project_id: project.id,
      signal: "log",
      bucket_start_at: bucket,
      source_complete: true
    )

    expect(result.status).to eq("mismatch")
    watermark = TelemetryProjectionWatermark.find_by!(project: project, signal: "log", bucket_start_at: bucket)
    expect(watermark).not_to be_complete
    expect(watermark.accepted_count).to eq(1)
    expect(watermark.accepted_checksum).to eq(event.uuid.delete("-").to_i(16))
    expect(watermark.delivered_count).to eq(0)
  end

  it "leaves the bucket explicitly incomplete while a projector delivery is active" do
    event = create(:ingest_event, :metric, project: project, occurred_at: bucket + 5.minutes)
    pending_delivery(event)
    checksum = event.uuid.delete("-").to_i(16)
    allow(client).to receive(:select_rows!).and_return(
      [ { "logical_count" => 1, "checksum" => checksum.to_s } ]
    )

    result = described_class.call(
      client: client,
      project_id: project.id,
      signal: "metric",
      bucket_start_at: bucket,
      source_complete: true
    )

    expect(result.status).to eq("incomplete_deliveries")
    expect(TelemetryProjectionWatermark.find_by!(project: project, signal: "metric", bucket_start_at: bucket)).not_to be_complete
  end

  it "publishes span coverage against the logical span facts" do
    span = create(:trace_span, project: project, started_at: bucket + 5.minutes)
    checksum = span.uuid.delete("-").to_i(16)
    allow(client).to receive(:select_rows!).and_return(
      [ { "logical_count" => 1, "checksum" => checksum.to_s } ]
    )

    result = described_class.call(
      client: client,
      project_id: project.id,
      signal: "span",
      bucket_start_at: bucket,
      source_complete: true
    )

    expect(result).to be_verified
    expect(TelemetryProjectionWatermark.find_by!(project: project, signal: "span")).to be_complete
    expect(client).to have_received(:select_rows!).with(a_string_including("logister.span_facts_v2", "started_at"))
  end

  def pending_delivery(event)
    key = TelemetryIdempotencyKey.create!(
      project: project,
      client_identifier: event.uuid,
      signal: event.event_type,
      record_type: "IngestEvent",
      record_id: event.id,
      recorded_at: event.occurred_at,
      expires_at: bucket + 120.days
    )
    outbox = TelemetryOutboxEvent.create!(
      project: project,
      telemetry_idempotency_key: key,
      client_identifier: event.uuid,
      signal: event.event_type,
      record_type: "IngestEvent",
      record_id: event.id,
      recorded_at: event.occurred_at,
      accepted_at: event.created_at,
      metadata: { "record_identifier" => event.uuid }
    )
    outbox.ensure_delivery!("clickhouse_event")
  end
end
