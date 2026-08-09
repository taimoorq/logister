# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::TelemetryLedgerCleanup, type: :model do
  let(:now) { Time.zone.parse("2026-08-08 16:30:00 UTC") }

  it "deletes only expired fully delivered ledgers and retains terminal failures" do
    completed_key, completed_delivery = ledger(status: :pending)
    expect(completed_delivery.claim!(now: now)).to be(true)
    completed_delivery.mark_completed!(lease_token: completed_delivery.lease_token, at: now)
    completed_key.update_column(:expires_at, now - 1.day)

    terminal_key, terminal_delivery = ledger(status: :pending)
    expect(terminal_delivery.claim!(now: now)).to be(true)
    terminal_delivery.mark_failed!(
      StandardError.new("poison"),
      lease_token: terminal_delivery.lease_token,
      terminal: true,
      at: now
    )
    terminal_key.update_column(:expires_at, now - 1.day)

    expect {
      expect(described_class.call(expired_before: now)).to eq(1)
    }.to change(TelemetryIdempotencyKey, :count).by(-1)
      .and change(TelemetryOutboxEvent, :count).by(-1)
      .and change(TelemetryDelivery, :count).by(-1)

    expect(TelemetryIdempotencyKey.exists?(completed_key.id)).to be(false)
    expect(TelemetryIdempotencyKey.exists?(terminal_key.id)).to be(true)
    expect(terminal_delivery.reload).to be_terminal_failed
  end

  it "bounds old complete and mismatched watermarks while retaining active delivery buckets" do
    old_bucket = now - TelemetryProjectionWatermark::RETENTION - 1.hour
    removable = TelemetryProjectionWatermark.create!(
      project: create(:project),
      signal: "log",
      destination: "clickhouse_event",
      bucket_start_at: old_bucket,
      complete_at: old_bucket,
      accepted_count: 0,
      delivered_count: 0
    )
    _key, active_delivery = ledger(status: :pending)
    active_watermark = TelemetryProjectionWatermark.find_by!(
      project: active_delivery.project,
      signal: "metric",
      destination: "clickhouse_event"
    )
    active_watermark.update!(bucket_start_at: old_bucket)
    active_delivery.telemetry_outbox_event.update!(recorded_at: old_bucket)

    described_class.call(
      expired_before: now,
      watermarks_before: now - TelemetryProjectionWatermark::RETENTION
    )

    expect(TelemetryProjectionWatermark.exists?(removable.id)).to be(false)
    expect(TelemetryProjectionWatermark.exists?(active_watermark.id)).to be(true)
  end

  def ledger(status:)
    event = create(:ingest_event, :metric, occurred_at: now)
    key = TelemetryIdempotencyKey.create!(
      project: event.project,
      client_identifier: event.uuid,
      signal: event.event_type,
      record_type: "IngestEvent",
      record_id: event.id,
      recorded_at: event.occurred_at,
      expires_at: now + 1.day
    )
    outbox = TelemetryOutboxEvent.create!(
      project: event.project,
      telemetry_idempotency_key: key,
      client_identifier: event.uuid,
      signal: event.event_type,
      record_type: "IngestEvent",
      record_id: event.id,
      recorded_at: event.occurred_at,
      accepted_at: now,
      metadata: { "record_identifier" => event.uuid }
    )
    delivery = outbox.ensure_delivery!("clickhouse_event")
    delivery.update!(status: status, available_at: now)
    [ key, delivery ]
  end
end
