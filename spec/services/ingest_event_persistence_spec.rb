# frozen_string_literal: true

require "rails_helper"

RSpec.describe IngestEventPersistence, type: :model do
  let(:project) { create(:project) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }
  let(:client_uuid) { "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
  let(:attributes) do
    {
      uuid: client_uuid,
      event_type: :error,
      level: "error",
      message: "Checkout failed",
      occurred_at: Time.current,
      context: { "environment" => "production" }
    }
  end

  around do |example|
    config = Rails.configuration.x.logister
    previous_mode = config.clickhouse_mode
    previous_enabled = config.clickhouse_enabled
    config.clickhouse_mode = "dual_write"
    config.clickhouse_enabled = true
    example.run
  ensure
    config.clickhouse_mode = previous_mode
    config.clickhouse_enabled = previous_enabled
  end

  it "commits the event, idempotency key, outbox, and required intents together" do
    result = nil

    expect {
      result = described_class.new(project: project, api_key: api_key, attributes: attributes).call
    }.to change(IngestEvent, :count).by(1)
      .and change(TelemetryIdempotencyKey, :count).by(1)
      .and change(TelemetryOutboxEvent, :count).by(1)
      .and change(TelemetryDelivery, :count).by(2)

    expect(result).not_to be_duplicate
    expect(result.outbox_event.telemetry_deliveries.pluck(:destination)).to contain_exactly(
      "clickhouse_event",
      "error_grouping"
    )
    expect(result.outbox_event.metadata).to include(
      "record_identifier" => client_uuid,
      "request_context" => {}
    )
  end

  it "rolls the accepted event back if durable intent creation fails" do
    allow(TelemetryOutboxEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "outbox unavailable")
    event_count = IngestEvent.count
    key_count = TelemetryIdempotencyKey.count

    expect {
      described_class.new(project: project, api_key: api_key, attributes: attributes).call
    }.to raise_error(ActiveRecord::StatementInvalid, /outbox unavailable/)

    expect(IngestEvent.count).to eq(event_count)
    expect(TelemetryIdempotencyKey.count).to eq(key_count)
  end

  it "repairs a newly configured destination on the duplicate path" do
    Rails.configuration.x.logister.clickhouse_mode = "disabled"
    Rails.configuration.x.logister.clickhouse_enabled = false
    first = described_class.new(project: project, api_key: api_key, attributes: attributes).call
    expect(first.outbox_event.telemetry_deliveries.pluck(:destination)).to contain_exactly("error_grouping")

    Rails.configuration.x.logister.clickhouse_mode = "dual_write"
    Rails.configuration.x.logister.clickhouse_enabled = true

    expect {
      duplicate = described_class.new(project: project, api_key: api_key, attributes: attributes).call
      expect(duplicate).to be_duplicate
      expect(duplicate.event).to eq(first.event)
    }.not_to change(IngestEvent, :count)

    expect(first.outbox_event.reload.telemetry_deliveries.pluck(:destination)).to contain_exactly(
      "clickhouse_event",
      "error_grouping"
    )
  end

  it "accepts a retry from immutable ledger metadata after its source is retired" do
    Rails.configuration.x.logister.clickhouse_mode = "disabled"
    Rails.configuration.x.logister.clickhouse_enabled = false
    log_attributes = attributes.merge(event_type: :log)
    first = described_class.new(project: project, api_key: api_key, attributes: log_attributes).call
    key = first.outbox_event.telemetry_idempotency_key
    accepted_metadata = key.acceptance_metadata.deep_dup

    key.update!(source_retired_at: Time.current)
    IngestEvent.for_partition_reference(id: first.event.id, occurred_at: first.event.occurred_at).delete_all

    Rails.configuration.x.logister.clickhouse_mode = "dual_write"
    Rails.configuration.x.logister.clickhouse_enabled = true
    expect do
      duplicate = described_class.new(project: project, api_key: api_key, attributes: log_attributes).call

      expect(duplicate).to be_duplicate
      expect(duplicate.event).to be_a(TelemetryAcceptanceTombstone)
      expect(duplicate.event).to have_attributes(uuid: first.event.uuid, id: first.event.id)
      expect(duplicate.outbox_event).to eq(first.outbox_event)
    end.not_to change(IngestEvent, :count)

    expect(key.reload.acceptance_metadata).to eq(accepted_metadata)
    expect(first.outbox_event.telemetry_deliveries.reload).to be_empty
    expect(first.outbox_event.repair_deliveries!([ "clickhouse_event" ])).to eq([])
    expect { first.outbox_event.ensure_delivery!("clickhouse_event") }
      .to raise_error(TelemetryOutboxEvent::SourceRetired, /archive replay/)
  end

  it "reports an identity conflict when a ledger source disappears without retirement" do
    Rails.configuration.x.logister.clickhouse_mode = "disabled"
    Rails.configuration.x.logister.clickhouse_enabled = false
    log_attributes = attributes.merge(event_type: :log)
    first = described_class.new(project: project, api_key: api_key, attributes: log_attributes).call
    IngestEvent.for_partition_reference(id: first.event.id, occurred_at: first.event.occurred_at).delete_all

    duplicate = described_class.new(project: project, api_key: api_key, attributes: log_attributes).call

    expect(duplicate).not_to be_duplicate
    expect(duplicate.event).not_to be_persisted
    expect(duplicate.event.errors[:uuid]).to include("has already been used for another telemetry signal")
  end

  it "scopes an explicit source UUID to its project" do
    other_project = create(:project)
    other_key = create(:api_key, project: other_project, user: other_project.user)

    first = described_class.new(project: project, api_key: api_key, attributes: attributes).call
    second = described_class.new(project: other_project, api_key: other_key, attributes: attributes).call

    expect(first).not_to be_duplicate
    expect(second).not_to be_duplicate
    expect(IngestEvent.where(uuid: client_uuid).pluck(:project_id)).to contain_exactly(project.id, other_project.id)
  end

  it "persists a server-owned reporting interval and receipt clock for delayed mobile evidence" do
    mobile_project = create(:project, :ios)
    mobile_key = create(:api_key, project: mobile_project, user: mobile_project.user)
    received_at = Time.zone.parse("2026-08-09T12:00:00Z")
    delayed_attributes = attributes.except(:occurred_at).merge(
      uuid: SecureRandom.uuid,
      context: {
        "platform" => "ios",
        "diagnostic" => {
          "source" => "metrickit",
          "kind" => "hang",
          "reporting_period" => {
            "start" => "2026-08-01T00:00:00Z",
            "end" => "2026-08-02T00:00:00Z"
          }
        }
      }
    )

    travel_to(received_at) do
      result = described_class.new(
        project: mobile_project,
        api_key: mobile_key,
        attributes: delayed_attributes
      ).call
      evidence = TelemetryEvidence.for(result.event)

      expect(result.event.occurred_at).to eq(Time.zone.parse("2026-08-02T00:00:00Z"))
      expect(evidence).to be_reporting_interval
      expect(evidence.received_at).to eq(received_at)
      expect(result.outbox_event.recorded_at).to eq(result.event.occurred_at)
      expect(result.outbox_event.accepted_at).to eq(received_at)
      expect(result.outbox_event.telemetry_idempotency_key.acceptance_metadata.fetch("evidence")).to include(
        "source" => "metrickit",
        "kind" => "hang",
        "time_precision" => "reporting_interval",
        "reporting_start" => "2026-08-01T00:00:00.000000Z",
        "reporting_end" => "2026-08-02T00:00:00.000000Z",
        "received_at" => "2026-08-09T12:00:00.000000Z"
      )
    end
  end
end
