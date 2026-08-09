# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::TelemetryProjector, type: :model do
  include ActiveJob::TestHelper

  let(:now) { Time.zone.parse("2026-08-08 16:30:00 UTC") }
  let(:clock) { -> { now } }
  let(:project) { create(:project) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }
  let(:clickhouse_client) do
    instance_double(
      Logister::ClickhouseClient,
      enabled?: true,
      insert_events!: nil,
      insert_spans!: nil
    )
  end

  before do
    allow(Logister::ClickhouseFailureReporter).to receive(:report_event_failure)
    allow(Logister::ClickhouseFailureReporter).to receive(:report_span_failure)
  end

  it "claims same-project signal-hour facts and sends one gzip/deduplicated batch" do
    deliveries = 2.times.map do |index|
      event = create(
        :ingest_event,
        :metric,
        project: project,
        api_key: api_key,
        occurred_at: now - (10 + index).minutes
      )
      ledger_delivery(event, destination: "clickhouse_event")
    end

    result = described_class.new(clickhouse_client: clickhouse_client, now: clock).call

    expect(result).to have_attributes(claimed: 2, completed: 2, retried: 0, terminal_failed: 0)
    expect(clickhouse_client).to have_received(:insert_events!).with(
      satisfy { |rows| rows.length == 2 && rows.map { |row| row.fetch(:event_id) }.sort == deliveries.map { |delivery| delivery.telemetry_outbox_event.metadata.fetch("record_identifier") }.sort },
      deduplication_token: match(/\Alogister-v1-clickhouse_event-[0-9a-f]{64}\z/),
      gzip: true
    ).once
    expect(deliveries.map { |delivery| delivery.reload.batch_key }.uniq.length).to eq(1)

    watermark = TelemetryProjectionWatermark.find_by!(
      project: project,
      signal: "metric",
      destination: "clickhouse_event",
      bucket_start_at: now.beginning_of_hour
    )
    expect(watermark).to have_attributes(accepted_count: 2, delivered_count: 2, terminal_failure_count: 0)
    expect(watermark).to be_complete
  end

  it "reuses the deterministic batch identity after an ambiguous retry without inflating the watermark" do
    deliveries = 2.times.map do |index|
      event = create(:ingest_event, :metric, project: project, api_key: api_key, occurred_at: now - index.minutes)
      ledger_delivery(event, destination: "clickhouse_event")
    end
    failing_client = instance_double(Logister::ClickhouseClient, enabled?: true)
    allow(failing_client).to receive(:insert_events!).and_raise(Logister::ClickhouseClient::Error, "connection closed after write")

    first = described_class.new(clickhouse_client: failing_client, now: clock).call
    batch_key = deliveries.first.reload.batch_key

    expect(first).to have_attributes(retried: 2, completed: 0)
    expect(deliveries.map { |delivery| delivery.reload.status }.uniq).to eq([ "retrying" ])

    retry_time = now + 3.seconds
    second = described_class.new(clickhouse_client: clickhouse_client, now: -> { retry_time }).call

    expect(second).to have_attributes(completed: 2, retried: 0)
    expect(clickhouse_client).to have_received(:insert_events!).with(
      anything,
      deduplication_token: batch_key,
      gzip: true
    ).once
    watermark = TelemetryProjectionWatermark.find_by!(project: project, signal: "metric", destination: "clickhouse_event")
    expect(watermark).to have_attributes(accepted_count: 2, delivered_count: 2)
    expect(watermark.accepted_checksum).to eq(watermark.delivered_checksum)
  end

  it "projects normalized transaction status and duration into typed ClickHouse fields" do
    event = create(
      :ingest_event,
      :transaction,
      project: project,
      api_key: api_key,
      occurred_at: now - 5.minutes,
      context: {
        "transaction_name" => "POST /checkout",
        "transaction_status" => "503",
        "duration_ms" => "182.5"
      }
    )
    ledger_delivery(event, destination: "clickhouse_event")

    described_class.new(clickhouse_client: clickhouse_client, now: clock).call

    expect(clickhouse_client).to have_received(:insert_events!).with(
      [ hash_including(
        event_id: event.uuid,
        identity_checksum: event.uuid.delete("-").to_i(16),
        transaction_status: "503",
        duration_ms: 182.5
      ) ],
      deduplication_token: match(/\Alogister-v1-clickhouse_event-/),
      gzip: true
    )
  end

  it "projects grouping, deployment indexing, and monitor derivation asynchronously" do
    error = create(:ingest_event, project: project, api_key: api_key, occurred_at: now, fingerprint: "async-group")
    error_delivery = ledger_delivery(error, destination: "error_grouping")

    expect {
      described_class.new(clickhouse_client: clickhouse_client, now: clock).call
    }.to change(ErrorGroup, :count).by(1)
    expect(error_delivery.reload).to be_completed

    create(:project_source_repository, project: project, full_name: "acme/storefront")
    deployment_event = create(
      :ingest_event,
      :transaction,
      project: project,
      api_key: api_key,
      occurred_at: now,
      context: {
        "release" => "2026.08.08",
        "environment" => "production",
        "repository" => "acme/storefront",
        "commit_sha" => "abcdef1234567"
      }
    )
    deployment_delivery = ledger_delivery(deployment_event, destination: "deployment_index")

    expect {
      described_class.new(clickhouse_client: clickhouse_client, now: clock).call
    }.to change(ProjectDeployment, :count).by(1)
    expect(deployment_delivery.reload).to be_completed

    check_in = create(:ingest_event, :check_in, project: project, api_key: api_key, occurred_at: now)
    monitor_delivery = ledger_delivery(check_in, destination: "check_in_monitor")

    expect {
      described_class.new(clickhouse_client: clickhouse_client, now: clock).call
    }.to change(CheckInMonitor, :count).by(1)
    expect(monitor_delivery.reload).to be_completed
  end

  it "retries deployment projection infrastructure failures instead of acknowledging lost work" do
    event = create(:ingest_event, :transaction, project: project, api_key: api_key, occurred_at: now)
    delivery = ledger_delivery(event, destination: "deployment_index")
    allow(ProjectDeploymentIndexer).to receive(:from_event)
      .and_raise(ActiveRecord::ConnectionNotEstablished, "database unavailable")

    result = described_class.new(clickhouse_client: clickhouse_client, now: clock).call

    expect(result).to have_attributes(completed: 0, retried: 1, terminal_failed: 0)
    expect(delivery.reload).to be_retrying
    expect(delivery.last_error_class).to eq("ActiveRecord::ConnectionNotEstablished")
  end

  it "terminalizes invalid deployment projections in the inspectable delivery ledger" do
    event = create(:ingest_event, :transaction, project: project, api_key: api_key, occurred_at: now)
    delivery = ledger_delivery(event, destination: "deployment_index")
    invalid = ProjectDeploymentIndexer::Result.new(deployment: nil, indexed: false, errors: [ "Commit is invalid" ])
    allow(ProjectDeploymentIndexer).to receive(:from_event).and_return(invalid)

    result = described_class.new(clickhouse_client: clickhouse_client, now: clock).call

    expect(result).to have_attributes(completed: 0, retried: 0, terminal_failed: 1)
    expect(delivery.reload).to be_terminal_failed
    expect(delivery.last_error_class).to eq("Logister::TelemetryProjector::InvalidProjection")
  end

  it "moves a poison ClickHouse response to the inspectable DLQ and replays the whole deterministic batch" do
    event = create(:ingest_event, :metric, project: project, api_key: api_key, occurred_at: now)
    delivery = ledger_delivery(event, destination: "clickhouse_event")
    error = Logister::ClickhouseClient::ResponseError.new("bad row", status_code: 400)
    allow(clickhouse_client).to receive(:insert_events!).and_raise(error)

    result = described_class.new(clickhouse_client: clickhouse_client, now: clock).call

    expect(result.terminal_failed).to eq(1)
    expect(delivery.reload).to be_terminal_failed
    expect(delivery.last_error_class).to eq("Logister::ClickhouseClient::ResponseError")
    batch_key = delivery.batch_key

    TelemetryDeliveryReplayJob.perform_now(delivery.id, "operator" => "spec")

    expect(delivery.reload).to be_pending
    expect(delivery.attempts).to eq(0)
    expect(delivery.batch_key).to eq(batch_key)
    expect(delivery.metadata).to include("operator" => "spec")
    expect(TelemetryProjectionWatermark.find_by!(project: project, signal: "metric").terminal_failure_count).to eq(0)
  end

  it "does not replay an already completed delivery or inflate its watermark" do
    event = create(:ingest_event, :metric, project: project, api_key: api_key, occurred_at: now)
    delivery = ledger_delivery(event, destination: "clickhouse_event")
    expect(delivery.claim!(now: now)).to be(true)
    expect(delivery.mark_completed!(lease_token: delivery.lease_token, at: now)).to be(true)
    watermark = TelemetryProjectionWatermark.find_by!(project: project, signal: "metric")

    TelemetryDeliveryReplayJob.perform_now(delivery.id, "operator" => "spec")

    expect(delivery.reload).to be_completed
    expect(watermark.reload).to have_attributes(accepted_count: 1, delivered_count: 1)
  end

  it "terminalizes an expired final lease instead of leaving it processing forever" do
    event = create(:ingest_event, :metric, project: project, api_key: api_key, occurred_at: now)
    delivery = ledger_delivery(event, destination: "clickhouse_event")
    delivery.update!(
      status: :processing,
      attempts: TelemetryDelivery::MAX_ATTEMPTS,
      leased_at: now - 5.minutes,
      lease_expires_at: now - 1.minute,
      lease_token: SecureRandom.uuid
    )

    expect(TelemetryDelivery.claim_batch(limit: 10, now: now)).to be_empty

    expect(delivery.reload).to be_terminal_failed
    expect(delivery.last_error_class).to eq("TelemetryDelivery::LeaseExpired")
    expect(TelemetryProjectionWatermark.find_by!(project: project, signal: "metric").terminal_failure_count).to eq(1)
  end

  it "refuses an already leased write when project purge becomes pending" do
    event = create(:ingest_event, :metric, project: project, api_key: api_key, occurred_at: now)
    delivery = ledger_delivery(event, destination: "clickhouse_event")
    expect(delivery.claim!(now: now)).to be(true)
    project.update!(purge_requested_at: now)

    projector = described_class.new(clickhouse_client: clickhouse_client, now: clock)
    projector.send(:project_clickhouse, [ delivery ])

    expect(clickhouse_client).not_to have_received(:insert_events!)
    expect(delivery.reload).to be_terminal_failed
    expect(delivery.last_error_class).to eq("Logister::TelemetryProjector::ProjectPurging")
  end

  it "rechecks the purge tombstone inside the project write fence" do
    event = create(:ingest_event, :metric, project: project, api_key: api_key, occurred_at: now)
    delivery = ledger_delivery(event, destination: "clickhouse_event")
    expect(delivery.claim!(now: now)).to be(true)
    project.update!(purge_requested_at: now)

    projector = described_class.new(clickhouse_client: clickhouse_client, now: clock)
    allow(projector).to receive(:ensure_project_active!).and_return(true)
    projector.send(:project_clickhouse, [ delivery ])

    expect(clickhouse_client).not_to have_received(:insert_events!)
    expect(delivery.reload).to be_terminal_failed
    expect(delivery.last_error_class).to eq("Logister::TelemetryProjector::ProjectPurging")
  end

  def ledger_delivery(record, destination:)
    recorded_at = TelemetryIdempotencyKey.recorded_at_for(record)
    key = TelemetryIdempotencyKey.create!(
      project: record.project,
      client_identifier: record.uuid,
      signal: record.is_a?(TraceSpan) ? "span" : record.event_type,
      record_type: record.class.base_class.name,
      record_id: record.id,
      recorded_at: recorded_at,
      expires_at: now + TelemetryIdempotencyKey::RETENTION
    )
    outbox = TelemetryOutboxEvent.create!(
      project: record.project,
      telemetry_idempotency_key: key,
      client_identifier: record.uuid,
      signal: key.signal,
      record_type: key.record_type,
      record_id: key.record_id,
      recorded_at: recorded_at,
      accepted_at: now,
      metadata: {
        "record_identifier" => record.uuid,
        "request_context" => {},
        "routing" => { "send_notifications" => true }
      }
    )
    outbox.ensure_delivery!(destination).tap { |delivery| delivery.update!(available_at: now) }
  end
end
