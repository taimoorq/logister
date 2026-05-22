# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::SpanIngestor, type: :model do
  let(:span) { create(:trace_span) }
  let(:fake_client) do
    Class.new do
      attr_reader :payload
      def enabled?; true; end
      def insert_span!(attrs); @payload = attrs; end
    end.new
  end

  it "maps trace spans to ClickHouse payloads" do
    span.update!(
      trace_id: "trace-123",
      span_id: "span-123",
      parent_span_id: "parent-123",
      name: "GET /checkout",
      kind: "server",
      status: "ok",
      duration_ms: 180.25,
      context: {
        "environment" => "production",
        "service" => "checkout",
        "release" => "sha123",
        "route" => "GET /checkout",
        "request_id" => "req-123",
        "tags" => { "region" => "us-east-1" }
      }
    )

    described_class.new(
      span: span,
      request_context: { ip: "127.0.0.1", user_agent: "LogisterTest/1.0" },
      clickhouse_client: fake_client
    ).call

    payload = fake_client.payload
    expect(payload[:span_id]).to eq(span.uuid)
    expect(payload[:trace_id]).to eq("trace-123")
    expect(payload[:external_span_id]).to eq("span-123")
    expect(payload[:parent_span_id]).to eq("parent-123")
    expect(payload[:kind]).to eq("server")
    expect(payload[:duration_ms]).to eq(180.25)
    expect(payload[:environment]).to eq("production")
    expect(payload[:route]).to eq("GET /checkout")
    expect(payload[:request_id]).to eq("req-123")
    expect(payload[:tags]).to eq({ "region" => "us-east-1" })
    expect(payload[:ip]).to eq("127.0.0.1")
  end

  it "does not call insert when ClickHouse is disabled" do
    disabled_client = instance_double(Logister::ClickhouseClient, enabled?: false)
    expect(disabled_client).not_to receive(:insert_span!)
    described_class.new(span: span, request_context: {}, clickhouse_client: disabled_client).call
  end
end
