# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260911190000_create_telemetry_projection_batches")

RSpec.describe "Batched telemetry projection", type: :model do
  let(:now) { Time.current.change(usec: 0) }
  let(:project) { create(:project) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }
  let(:client) do
    instance_double(Logister::ClickhouseClient, enabled?: true,
      insert_event_payload!: nil, insert_span_payload!: nil, insert_events!: nil)
  end

  around do |example|
    previous = ENV["LOGISTER_BATCHED_PROJECTION"]
    ENV["LOGISTER_BATCHED_PROJECTION"] = "true"
    example.run
  ensure
    previous.nil? ? ENV.delete("LOGISTER_BATCHED_PROJECTION") : ENV["LOGISTER_BATCHED_PROJECTION"] = previous
  end

  before do
    allow(Logister::ClickhouseFailureReporter).to receive(:report_event_failure)
    allow(Logister::ClickhouseFailureReporter).to receive(:report_span_failure)
  end

  it "keeps source reads and acknowledgement queries constant for 1, 20 and 200-row batches" do
    counts = [ 1, 20, 200 ].map do |size|
      deliveries = Array.new(size) { accept_delivery }
      sql = capture_sql do
        result = projector.call
        expect(result).to have_attributes(claimed: size, completed: size, retried: 0, terminal_failed: 0)
      end
      expect(sql.count { |statement| statement.match?(/SELECT .*FROM "ingest_events"/) }).to eq(1)
      expect(TelemetryDelivery.where(id: deliveries.map(&:id)).pluck(:status)).to all(eq("completed"))
      expect(TelemetryProjectionBatch.count).to eq(0)
      sql.length
    end

    expect(counts.max - counts.min).to be <= 2
    expect(watermark).to have_attributes(accepted_count: 221, delivered_count: 221)
    expect(watermark.accepted_checksum).to eq(watermark.delivered_checksum)
  end

  it "projects a span through its own persisted body and watermark destination" do
    span = create(:trace_span, project: project, api_key: api_key, started_at: now)
    outbox = Logister::TelemetryAcceptanceLedger.accept!(record: span, client_identifier: span.uuid,
      clickhouse_writable: true, installation: nil)
    outbox.telemetry_deliveries.update_all(available_at: now)

    expect(projector.call).to have_attributes(claimed: 1, completed: 1)

    expect(client).to have_received(:insert_span_payload!).with(
      satisfy { |body| JSON.parse(body).fetch("span_id") == span.uuid },
      deduplication_token: match(/\Alogister-v1-clickhouse_span-/), gzip: true
    )
    expect(client).not_to have_received(:insert_event_payload!)
    expect(TelemetryProjectionWatermark.find_by!(project: project, signal: "span", destination: "clickhouse_span")).to be_complete
  end

  it "retries the exact committed HTTP body after an ambiguous success and source changes, without loading sources" do
    deliveries = 2.times.map { accept_delivery }
    bodies = []
    allow(client).to receive(:insert_event_payload!) do |body, **_options|
      bodies << body
      raise Logister::ClickhouseClient::Error, "response lost after insert" if bodies.length == 1
    end

    expect(projector.call).to have_attributes(retried: 2)
    batch = TelemetryProjectionBatch.sole
    expect(batch.payload).to eq(bodies.first)
    expect(batch.delivery_ids).to eq(deliveries.map(&:id))
    source = deliveries.first.telemetry_outbox_event.source_record
    IngestEvent.for_partition_reference(id: source.id, occurred_at: source.occurred_at)
      .where(project_id: project.id).update_all(message: "changed after the first insert", updated_at: now + 1.second)
    project.update!(slug: "renamed-after-first-insert")
    ENV["LOGISTER_BATCHED_PROJECTION"] = "false"

    sql = capture_sql { expect(projector(at: now + 3.seconds).call).to have_attributes(completed: 2) }

    expect(bodies.length).to eq(2)
    expect(bodies.last).to eq(bodies.first)
    expect(sql.grep(/SELECT .*FROM "ingest_events"/)).to be_empty
    expect(watermark).to be_complete
    expect(TelemetryProjectionBatch.count).to eq(0)
  end

  it "fails closed on a corrupt persisted payload without issuing an external insert" do
    deliveries, batch = prepared_batch
    batch.update_column(:compressed_payload, "not gzip")
    deliveries.each { |delivery| delivery.mark_failed!(StandardError.new("retry"), at: now) }

    expect(projector(at: now + 3.seconds).call).to have_attributes(completed: 0, terminal_failed: 2)

    expect(client).not_to have_received(:insert_event_payload!)
    expect(TelemetryProjectionBatch.exists?(batch.id)).to be(true)
  end

  it "prevents a schema rollback from deleting an incomplete batch payload" do
    prepared_batch

    expect { CreateTelemetryProjectionBatches.new.down }.to raise_error(ActiveRecord::IrreversibleMigration, /Drain persisted projection batches/)

    expect(TelemetryProjectionBatch.count).to eq(1)
  end

  it "removes the retained payload through the real PostgreSQL project purge adapter" do
    _deliveries, batch = prepared_batch
    purge = Logister::ProjectPurgeRequest.new(project: project, requested_by: project.user, enqueue: false).call

    result = Logister::ProjectPurgeAdapters::Postgresql.new(project_purge: purge).call

    expect(result).to include(status: "completed", project_deleted: true)
    expect(TelemetryProjectionBatch.exists?(batch.id)).to be(false)
    expect(purge.reload.project).to be_nil
  end

  it "reconstructs a partial legacy acknowledgement with the whole original body and counts only the remaining delivery" do
    deliveries, original_body, key = legacy_retry
    first = deliveries.first.reload
    first.claim!(now: now + 3.seconds)
    first.mark_completed!(lease_token: first.lease_token, at: now + 3.seconds)

    expect(projector(at: now + 3.seconds).call).to have_attributes(claimed: 1, completed: 1)

    expect(client).to have_received(:insert_event_payload!).with(original_body, deduplication_token: key, gzip: true).once
    expect(watermark).to have_attributes(accepted_count: 2, delivered_count: 2)
    expect(watermark).to be_complete
  end

  it "does not send a truncated legacy payload when an original member is unavailable" do
    deliveries, = legacy_retry
    TelemetryDelivery.where(id: deliveries.first.id).delete_all

    expect(projector(at: now + 3.seconds).call).to have_attributes(claimed: 1, completed: 0, terminal_failed: 1)

    expect(client).not_to have_received(:insert_event_payload!)
    expect(deliveries.last.reload.last_error_class).to eq("TelemetryProjectionBatch::InvalidPayload")
  end

  it "does not claim to reconstruct an original legacy body after its source or project fallback changed" do
    legacy_retry
    project.update!(slug: "changed-without-an-original-snapshot")

    expect(projector(at: now + 3.seconds).call).to have_attributes(completed: 0, terminal_failed: 2)

    expect(client).not_to have_received(:insert_event_payload!)
    expect(watermark).to have_attributes(delivered_count: 0, terminal_failure_count: 2)
  end

  it "rolls batch identity and the persisted payload back when one lease was lost" do
    2.times { accept_delivery }
    deliveries = TelemetryDelivery.claim_batch(limit: 2, now: now)
    TelemetryDelivery.where(id: deliveries.first.id).update_all(lease_token: SecureRandom.uuid)

    expect do
      TelemetryProjectionBatch.prepare!(deliveries: deliveries, batch_key: "ownership-test", payload: "{}\n")
    end.to raise_error(TelemetryDelivery::BatchOwnershipLost)

    expect(TelemetryProjectionBatch.count).to eq(0)
    expect(TelemetryDelivery.where(id: deliveries.map(&:id)).pluck(:batch_key)).to eq([ nil, nil ])
  end

  it "rolls completion, counts and payload cleanup back together if the watermark write fails" do
    deliveries, batch = prepared_batch
    allow(TelemetryProjectionWatermark).to receive(:record_delivered_batch!).and_wrap_original do |method, *args, **kwargs|
      method.call(*args, **kwargs)
      raise ActiveRecord::StatementInvalid, "injected after watermark write"
    end

    expect { batch.acknowledge!(deliveries, at: now) }.to raise_error(ActiveRecord::StatementInvalid)

    expect(TelemetryDelivery.where(id: deliveries.map(&:id)).pluck(:status)).to eq([ "processing", "processing" ])
    expect(watermark).to have_attributes(delivered_count: 0, delivered_checksum: 0)
    expect(TelemetryProjectionBatch.exists?(batch.id)).to be(true)
    allow(TelemetryProjectionWatermark).to receive(:record_delivered_batch!).and_call_original
    expect(batch.reload.acknowledge!(deliveries, at: now)).to match_array(deliveries.map(&:id))
    expect(TelemetryDelivery.mark_completed_batch!(deliveries, at: now)).to be_empty
    expect(watermark).to have_attributes(delivered_count: 2)
  end

  it "excludes a stale owner from progress and retains the payload until the current owner completes" do
    deliveries, batch = prepared_batch
    fresh_token = SecureRandom.uuid
    TelemetryDelivery.where(id: deliveries.first.id).update_all(lease_token: fresh_token)

    expect(batch.acknowledge!(deliveries, at: now)).to eq([ deliveries.last.id ])
    expect(watermark).to have_attributes(delivered_count: 1)
    expect(TelemetryProjectionBatch.exists?(batch.id)).to be(true)
    expect(batch.acknowledge!([ deliveries.first.reload ], at: now)).to eq([ deliveries.first.id ])
    expect(watermark).to have_attributes(delivered_count: 2)
    expect(TelemetryProjectionBatch.exists?(batch.id)).to be(false)
  end

  it "retains completed legacy source and ledger members until the rest of their batch finishes" do
    deliveries, = legacy_retry
    first = deliveries.first.reload
    first.claim!(now: now + 3.seconds)
    first.mark_completed!(lease_token: first.lease_token, at: now + 3.seconds)
    keys = deliveries.map { |delivery| delivery.telemetry_outbox_event.telemetry_idempotency_key_id }
    TelemetryIdempotencyKey.where(id: keys).update_all(expires_at: now - 1.day)

    expect(Logister::TelemetryLedgerCleanup.call(expired_before: now)).to eq(0)
    source_scope = IngestEvent.where(project_id: project.id)
    expect(Logister::TelemetryRetentionProtection.without_incomplete_deliveries(source_scope)).to be_empty

    expect(projector(at: now + 3.seconds).call).to have_attributes(completed: 1)
    expect(Logister::TelemetryRetentionProtection.without_incomplete_deliveries(source_scope).count).to eq(2)
    expect(Logister::TelemetryLedgerCleanup.call(expired_before: now)).to eq(2)
  end

  it "cleans a completed payload left by an old worker without discarding incomplete or terminal batches" do
    deliveries, batch = prepared_batch
    deliveries.each { |delivery| delivery.mark_completed!(lease_token: delivery.lease_token, at: now) }

    expect { TelemetryProjectionBatch.cleanup_completed! }.to change(TelemetryProjectionBatch, :count).by(-1)
    expect(TelemetryProjectionBatch.exists?(batch.id)).to be(false)
    pending_deliveries, pending_batch = prepared_batch
    pending_deliveries.first.mark_failed!(StandardError.new("poison"), terminal: true, at: now)
    TelemetryProjectionBatch.cleanup_completed!
    expect(TelemetryProjectionBatch.exists?(pending_batch.id)).to be(true)
  end

  private

  def accept_delivery
    result = IngestEventPersistence.new(project: project, api_key: api_key,
      attributes: { uuid: SecureRandom.uuid, event_type: "log", message: "batch café 🌍", occurred_at: now },
      clickhouse_writable: true, installation: nil).call
    result.outbox_event.telemetry_deliveries.find_by!(destination: "clickhouse_event")
      .tap { |delivery| delivery.update_columns(available_at: now) }
  end

  def projector(at: now)
    Logister::TelemetryProjector.new(clickhouse_client: client, now: -> { at })
  end

  def watermark
    TelemetryProjectionWatermark.find_by!(project: project, signal: "log", destination: "clickhouse_event")
  end

  def prepared_batch
    2.times { accept_delivery }
    deliveries = TelemetryDelivery.claim_batch(limit: 2, now: now)
    batch = TelemetryProjectionBatch.prepare!(deliveries: deliveries,
      batch_key: "test-#{SecureRandom.hex(8)}", payload: "{}\n")
    [ deliveries, batch ]
  end

  def legacy_retry
    deliveries = 2.times.map { accept_delivery }
    body = nil
    key = nil
    ENV["LOGISTER_BATCHED_PROJECTION"] = "false"
    allow(client).to receive(:insert_events!) do |rows, **options|
      body = "#{rows.map(&:to_json).join("\n")}\n"
      key = options.fetch(:deduplication_token)
      raise Logister::ClickhouseClient::Error, "legacy response lost"
    end
    expect(projector.call).to have_attributes(retried: 2)
    ENV["LOGISTER_BATCHED_PROJECTION"] = "true"
    [ deliveries, body, key ]
  end

  def capture_sql
    queries = []
    callback = ->(event) do
      queries << event.payload.fetch(:sql) unless event.payload[:cached] || event.payload[:name].in?(%w[SCHEMA TRANSACTION])
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end
end
