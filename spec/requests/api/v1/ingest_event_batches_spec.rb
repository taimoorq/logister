# frozen_string_literal: true

require "rails_helper"
require "zlib"

RSpec.describe "Api::V1::IngestEvent batches", type: :request do
  let(:auth_headers) do
    {
      "Authorization" => "Bearer test-token-one",
      "Content-Type" => "application/x-ndjson",
      "Content-Encoding" => "gzip",
      "X-Logister-Batch-Id" => "sdk-batch-123",
      "User-Agent" => "LogisterBatchTest/1.0"
    }
  end

  before do
    allow(Logister).to receive(:report_log).and_return(true)
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

  it "atomically accepts gzip NDJSON events and spans with per-envelope results" do
    events = [
      {
        uuid: "11111111-1111-4111-8111-111111111111",
        event_type: "log",
        level: "info",
        message: "one",
        occurred_at: "2026-08-08T12:00:00Z",
        context: { environment: "production" }
      },
      {
        uuid: "22222222-2222-4222-8222-222222222222",
        event_type: "span",
        name: "GET /checkout",
        trace_id: "trace-batch-1",
        span_id: "span-batch-1",
        kind: "server",
        duration_ms: 12.5,
        started_at: "2026-08-08T12:00:00Z",
        context: { environment: "production" }
      }
    ]

    expect do
      post batch_api_v1_ingest_events_path, params: gzip_ndjson(events), headers: auth_headers
    end.to change(IngestEvent, :count).by(1)
      .and change(TraceSpan, :count).by(1)
      .and have_enqueued_job(TelemetryProjectorJob)

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to include(
      "schema_version" => 1,
      "batch_id" => "sdk-batch-123",
      "status" => "accepted",
      "accepted" => 2,
      "duplicates" => 0
    )
    expect(response.parsed_body.fetch("results").map { |result| result.fetch("id") }).to eq(
      events.map { |event| event.fetch(:uuid) }
    )
  end

  it "replays the same batch idempotently with stable envelope identifiers" do
    events = [
      {
        uuid: "33333333-3333-4333-8333-333333333333",
        event_type: "log",
        message: "one",
        occurred_at: "2026-08-08T12:00:00Z"
      },
      {
        uuid: "44444444-4444-4444-8444-444444444444",
        event_type: "metric",
        message: "queue.depth",
        occurred_at: "2026-08-08T12:00:01Z",
        context: { value: 4 }
      }
    ]
    body = gzip_ndjson(events)

    post batch_api_v1_ingest_events_path, params: body, headers: auth_headers
    expect(response).to have_http_status(:accepted)

    expect do
      post batch_api_v1_ingest_events_path, params: body, headers: auth_headers
    end.not_to change(IngestEvent, :count)

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.fetch("duplicates")).to eq(2)
    expect(response.parsed_body.fetch("results")).to all(include("duplicate" => true))
  end

  it "rolls back newly valid envelopes when any envelope is invalid" do
    events = [
      {
        uuid: "55555555-5555-4555-8555-555555555555",
        event_type: "log",
        message: "valid",
        occurred_at: "2026-08-08T12:00:00Z"
      },
      {
        uuid: "66666666-6666-4666-8666-666666666666",
        event_type: "error"
      }
    ]

    expect do
      post batch_api_v1_ingest_events_path, params: gzip_ndjson(events), headers: auth_headers
    end.not_to change(IngestEvent, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.fetch("status")).to eq("rejected")
    expect(response.parsed_body.fetch("results").pluck("status")).to eq(%w[rolled_back rejected])
    expect(response.parsed_body.dig("results", 1, "errors")).to include("Message can't be blank")
  end

  it "counts every batch envelope against the tenant intake limit" do
    events = 3.times.map do |index|
      {
        uuid: format("77777777-7777-4777-8777-%012d", index),
        event_type: "log",
        message: "event #{index}",
        occurred_at: "2026-08-08T12:00:00Z"
      }
    end

    with_public_api_rate_limits(requests: 2) do
      expect do
        post batch_api_v1_ingest_events_path, params: gzip_ndjson(events), headers: auth_headers
      end.not_to change(IngestEvent, :count)
    end

    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body.fetch("error")).to eq("Rate limit exceeded")
  end

  it "rejects unsupported media types and malformed gzip before persistence" do
    post batch_api_v1_ingest_events_path,
      params: "{}\n",
      headers: auth_headers.except("Content-Encoding").merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:unsupported_media_type)
    expect(response.parsed_body.fetch("code")).to eq("unsupported_content_type")

    post batch_api_v1_ingest_events_path, params: "not-gzip", headers: auth_headers

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.fetch("code")).to eq("invalid_gzip")
  end

  it "returns controlled bad requests for non-object envelopes and invalid stable identities" do
    headers = auth_headers.except("Content-Encoding")

    expect do
      post batch_api_v1_ingest_events_path, params: "[]\n", headers: headers
    end.not_to change(IngestEvent, :count)

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.fetch("code")).to eq("invalid_envelope")

    expect do
      post batch_api_v1_ingest_events_path,
        params: { event: { event_type: "log", message: "missing identity" } }.to_json << "\n",
        headers: headers
    end.not_to change(IngestEvent, :count)

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.fetch("code")).to eq("missing_identity")

    expect do
      post batch_api_v1_ingest_events_path,
        params: { event: { event_id: "invalid", event_type: "log", message: "bad identity" } }.to_json << "\n",
        headers: headers
    end.not_to change(IngestEvent, :count)

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.fetch("code")).to eq("invalid_identity")
  end

  it "accepts event_id-only envelopes and normalizes the response identity" do
    uuid = "88888888-8888-4888-8888-888888888888"
    headers = auth_headers.except("Content-Encoding")
    body = { event: { event_id: uuid, event_type: "log", message: "event id" } }.to_json << "\n"

    post batch_api_v1_ingest_events_path, params: body, headers: headers

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.dig("results", 0, "id")).to eq(uuid)
  end

  private

  def gzip_ndjson(events)
    Zlib.gzip(events.map { |event| { event: event }.to_json }.join("\n") << "\n")
  end
end
