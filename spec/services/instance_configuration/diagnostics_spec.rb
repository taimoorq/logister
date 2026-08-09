# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstanceConfiguration::Diagnostics, type: :model do
  it "validates the required general settings without a network call" do
    result = described_class.call("general", values: InstanceConfiguration.values_for("general"))

    expect(result).to be_success
    expect(result.summary).to include("Canonical URLs")
  end

  it "requires both Redis and a registered Sidekiq worker" do
    redis = instance_double(Redis, ping: "PONG", close: nil)
    readiness = instance_double(Logister::SidekiqReadiness)
    partitioning = instance_double(Logister::IngestEventsPartitioning, partition_maintenance_status: {})
    allow(Redis).to receive(:new).and_return(redis)
    allow(Logister::SidekiqReadiness).to receive(:new).and_return(readiness)
    allow(Logister::IngestEventsPartitioning).to receive(:new).and_return(partitioning)
    allow(readiness).to receive(:call).and_return(
      "sidekiq_processes" => 0,
      "database_pool" => { "valid" => true }
    )

    result = described_class.call("background_jobs", values: InstanceConfiguration.values_for("background_jobs"))

    expect(result).not_to be_success
    expect(result.summary).to include("no Sidekiq worker")

    allow(readiness).to receive(:call).and_return(
      "sidekiq_processes" => 2,
      "database_pool" => { "valid" => true }
    )
    result = described_class.call("background_jobs", values: InstanceConfiguration.values_for("background_jobs"))

    expect(result).to be_success
    expect(result.details).to include("sidekiq_processes" => 2)
  end

  it "does a write, read, and cleanup check for local archives" do
    result = described_class.call("archive_storage", values: InstanceConfiguration.values_for("archive_storage"))

    expect(result).to be_success
    expect(result.summary).to include("write, read, and delete")
    expect(Dir.glob(Rails.root.join("storage/.logister-configuration-test-*"))).to be_empty
  end

  it "does not declare ClickHouse read-ready when retained coverage is short" do
    values = InstanceConfiguration.values_for(
      "clickhouse",
      overrides: { "clickhouse.mode" => "dual_write", "clickhouse.url" => "https://clickhouse.example" }
    )
    client = instance_double(
      Logister::ClickhouseClient,
      schema_status: { ready: true, healthy: true, database: "logister", missing_tables: [], schema_issues: [] },
      event_facts_table_name: "logister.event_facts_v2",
      span_facts_table_name: "logister.span_facts_v2",
      close: nil,
      circuit_breaker_status: { "state" => "closed" }
    )
    allow(client).to receive(:select_rows!).and_return([])
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
    create(:ingest_event, occurred_at: 3.hours.ago)

    result = described_class.call("clickhouse", values: values)

    expect(result).not_to be_success
    expect(result.details).to include("ready_for_reads" => false)
    expect(result.details.fetch("delivery_ledger")).to include("terminal_failures" => 0)
    expect(client).to have_received(:select_rows!).with(
      a_string_including("GROUP BY project_id, signal, bucket", "sum(toUInt256(identity_checksum))")
    )
  end

  it "tells an operator to finish the read cutover when dual-write coverage passes" do
    values = InstanceConfiguration.values_for(
      "clickhouse",
      overrides: { "clickhouse.mode" => "dual_write", "clickhouse.url" => "https://clickhouse.example" }
    )
    client = instance_double(
      Logister::ClickhouseClient,
      schema_status: { ready: true, healthy: true, database: "logister", missing_tables: [], schema_issues: [] },
      event_facts_table_name: "logister.event_facts_v2",
      span_facts_table_name: "logister.span_facts_v2",
      close: nil,
      circuit_breaker_status: { "state" => "closed" }
    )
    event = create(:ingest_event, :metric, occurred_at: 3.hours.ago)
    delivery = completed_clickhouse_delivery(event)
    coverage_finish = 1.hour.ago.utc.beginning_of_hour
    coverage_start = coverage_finish - 24.hours
    cursor = coverage_start
    while cursor < coverage_finish
      (Logister::ClickhouseCoverage::EVENT_SIGNALS + [ "span" ]).each do |signal|
        next if signal == "metric" && cursor == event.occurred_at.utc.beginning_of_hour

        TelemetryProjectionWatermark.seal_empty!(
          project_id: event.project_id,
          signal: signal,
          destination: signal == "span" ? "clickhouse_span" : "clickhouse_event",
          bucket_start_at: cursor
        )
      end
      cursor += 1.hour
    end
    checksum = Logister::TelemetryIdentity.normalize_uuid(event.uuid).delete("-").to_i(16)
    bucket_row = {
      "project_id" => event.project_id,
      "signal" => "metric",
      "bucket" => event.occurred_at.utc.beginning_of_hour.strftime("%Y-%m-%d %H:%M:%S"),
      "count" => 1,
      "checksum" => checksum.to_s
    }
    allow(client).to receive(:select_rows!).and_return(
      [ bucket_row ],
      [ { "record_identifier" => event.uuid } ]
    )
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)

    result = described_class.call("clickhouse", values: values)

    expect(result).to be_success
    expect(result.summary).to include("Switch to read preferred", "dashboard reads off PostgreSQL")
    expect(result.details).to include(
      "coverage_bucket_count" => 144,
      "coverage_gap_count" => 0,
      "ready_for_reads" => true
    )
    expect(result.details.fetch("sample_reconciliation")).to include(
      "expected_count" => 1,
      "present_count" => 1,
      "missing_count" => 0
    )
    expect(delivery.reload).to be_completed
  end

  it "rejects nonpositive public API limits" do
    values = InstanceConfiguration.values_for(
      "authentication",
      overrides: { "authentication.public_api_rate_limit_requests" => "0" }
    )

    result = described_class.call("authentication", values: values)

    expect(result).not_to be_success
    expect(result.summary).to include("positive integers")
  end


  def completed_clickhouse_delivery(event)
    key = TelemetryIdempotencyKey.create!(
      project: event.project,
      client_identifier: event.uuid,
      signal: event.event_type,
      record_type: "IngestEvent",
      record_id: event.id,
      recorded_at: event.occurred_at,
      expires_at: Time.current + TelemetryIdempotencyKey::RETENTION
    )
    outbox = TelemetryOutboxEvent.create!(
      project: event.project,
      telemetry_idempotency_key: key,
      client_identifier: event.uuid,
      signal: event.event_type,
      record_type: "IngestEvent",
      record_id: event.id,
      recorded_at: event.occurred_at,
      accepted_at: Time.current,
      metadata: { "record_identifier" => event.uuid }
    )
    delivery = outbox.ensure_delivery!("clickhouse_event")
    delivery.update!(available_at: Time.current)
    delivery.claim!(now: Time.current)
    delivery.mark_completed!(lease_token: delivery.lease_token, at: Time.current)
    delivery
  end
end
