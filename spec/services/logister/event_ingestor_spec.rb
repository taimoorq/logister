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
    expect(payload[:event_id]).to eq("7f2d5dca-0c4d-4f5e-9997-6f87f5460b88")
    expect(payload[:project_id]).to eq(event.project_id)
    expect(payload[:api_key_id]).to eq(event.api_key_id)
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

  it "uses fallback fingerprint when event has no fingerprint in context" do
    event.update!(fingerprint: nil, context: {})
    described_class.new(event: event, request_context: {}, clickhouse_client: fake_client).call
    expect(fake_client.payload[:fingerprint]).to be_present
    expect(fake_client.payload[:fingerprint].length).to eq(32)
  end
end
