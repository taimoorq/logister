# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::EventIngestor, type: :model do
  let(:event) { ingest_events(:one) }
  let(:fake_client) do
    Class.new do
      attr_reader :payload
      def enabled?; true; end
      def insert_event!(attrs); @payload = attrs; end
    end.new
  end

  before do
    event.update!(
      context: {
        "environment" => "production",
        "service" => "checkout-service",
        "release" => "sha123",
        "exception" => { "class" => "NoMethodError" },
        "transaction_name" => "POST /checkout",
        "tags" => { "region" => "us-east-1" },
        "event_id" => "7f2d5dca-0c4d-4f5e-9997-6f87f5460b88"
      }
    )
  end

  it "maps ingest event to clickhouse payload" do
    described_class.new(
      event: event,
      request_context: { ip: "127.0.0.1", user_agent: "LogisterTest/1.0" },
      clickhouse_client: fake_client
    ).call

    payload = fake_client.payload
    expect(payload[:event_id]).to eq(event.uuid)
    expect(payload[:identity_checksum]).to eq(event.uuid.delete("-").to_i(16))
    expect(payload[:project_id]).to eq(event.project_id)
    expect(payload[:api_key_id]).to eq(event.api_key_id)
    expect(payload[:projection_version]).to be_positive
    expect(payload[:occurred_at]).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\z/)
    expect(payload[:received_at]).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\z/)
    expect(payload[:event_type]).to eq("error")
    expect(payload[:environment]).to eq("production")
    expect(payload[:service]).to eq("checkout-service")
    expect(payload[:release]).to eq("sha123")
    expect(payload[:exception_class]).to eq("NoMethodError")
    expect(payload[:transaction_name]).to eq("POST /checkout")
    expect(payload[:tags]).to eq({ "region" => "us-east-1" })
    expect(payload[:ip]).to eq("127.0.0.1")
    expect(payload[:user_agent]).to eq("LogisterTest/1.0")
  end

  it "does not call insert when clickhouse is disabled" do
    disabled_client = instance_double(Logister::ClickhouseClient, enabled?: false)
    expect(disabled_client).not_to receive(:insert_event!)
    described_class.new(event: event, request_context: {}, clickhouse_client: disabled_client).call
  end

  it "does not mirror ClickHouse failure monitoring events back into ClickHouse" do
    event.update!(
      fingerprint: "logister:clickhouse_ingest:failure",
      context: {
        "clickhouse_ingest" => {
          "ingest_event_id" => 123,
          "error" => { "message" => "insert failed" }
        }
      }
    )
    client = instance_double(Logister::ClickhouseClient, enabled?: true)
    expect(client).not_to receive(:insert_event!)

    described_class.new(event: event, request_context: {}, clickhouse_client: client).call
  end

  it "does not let a rolling-deploy legacy job recreate data after the purge tombstone" do
    event.project.update!(purge_requested_at: Time.current)

    described_class.new(event: event, request_context: {}, clickhouse_client: fake_client).call

    expect(fake_client.payload).to be_nil
  end

  it "uses fallback fingerprint when event has no fingerprint in context" do
    event.update!(fingerprint: nil, context: {})
    described_class.new(event: event, request_context: {}, clickhouse_client: fake_client).call
    expect(fake_client.payload[:fingerprint]).to be_present
    expect(fake_client.payload[:fingerprint].length).to eq(32)
  end

  it "uses the persisted event UUID when the sender did not provide an event ID" do
    event.update!(context: {})

    described_class.new(event: event, request_context: {}, clickhouse_client: fake_client).call

    expect(fake_client.payload[:event_id]).to eq(event.uuid)
  end

  it "projects transaction values into typed analytical columns" do
    event.update!(
      event_type: :transaction,
      message: "POST /checkout",
      context: {
        "transaction_name" => "POST /checkout",
        "transaction_status" => "503",
        "duration_ms" => "182.5",
        "trace_id" => "trace-typed",
        "request_id" => "request-typed"
      }
    )

    described_class.new(event: event, request_context: {}, clickhouse_client: fake_client).call

    expect(fake_client.payload).to include(
      transaction_status: "503",
      duration_ms: 182.5,
      trace_id: "trace-typed",
      request_id: "request-typed",
      metric_name: "",
      metric_value: nil
    )
  end

  it "keeps check-in status separate from transaction status" do
    event.update!(
      event_type: :check_in,
      context: {
        "check_in_slug" => "nightly-import",
        "check_in_status" => "ok",
        "expected_interval_seconds" => 3600
      }
    )

    described_class.new(event: event, request_context: {}, clickhouse_client: fake_client).call

    expect(fake_client.payload).to include(
      transaction_status: "",
      check_in_slug: "nightly-import",
      check_in_status: "ok",
      check_in_expected_interval_seconds: 3600
    )
  end

  it "closes the default-owned ClickHouse client after legacy single-row delivery" do
    client = instance_double(Logister::ClickhouseClient, enabled?: true, insert_event!: nil, close: nil)
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)

    described_class.new(event: event, request_context: {}).call

    expect(client).to have_received(:close).once
  end
end
