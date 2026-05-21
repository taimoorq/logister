# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::IngestEvents", type: :request do
  describe "POST /api/v1/ingest_events" do
    before do
      allow(Logister).to receive(:report_log).and_return(true)
    end

    let(:valid_payload) do
      {
        event: {
          event_type: "error",
          level: "error",
          message: "NoMethodError",
          fingerprint: "nomethoderror-checkout",
          context: {
            environment: "production",
            service: "checkout-app",
            tags: { region: "us-east-1" },
            exception: {
              class: "NoMethodError",
              backtrace: [ "app/services/checkout_service.rb:12", "app/controllers/checkout_controller.rb:8" ]
            },
            metadata: {
              order_id: 123,
              feature_flags: [ "new-checkout" ]
            }
          }
        }
      }
    end

    let(:auth_headers) do
      { "Authorization" => "Bearer test-token-one", "User-Agent" => "LogisterTest/1.0" }
    end

    it "creates event and enqueues ClickhouseIngestJob" do
      expect {
        post api_v1_ingest_events_path, params: valid_payload, as: :json, headers: auth_headers
      }.to have_enqueued_job(ClickhouseIngestJob)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["status"]).to eq("accepted")
      expect(body["id"]).to be_present

      created = IngestEvent.order(:id).last
      expect(created.project_id).to eq(api_keys(:one).project_id)
      expect(created.api_key_id).to eq(api_keys(:one).id)
      expect(created.event_type).to eq("error")
      expect(created.context.dig("exception", "class") || created.context.dig(:exception, :class)).to eq("NoMethodError")
      expect(created.context.dig("metadata", "feature_flags", 0) || created.context.dig(:metadata, :feature_flags, 0)).to eq("new-checkout")
    end

    it "rejects unauthorized token" do
      post api_v1_ingest_events_path,
           params: { event: { event_type: "error", message: "NoMethodError", occurred_at: Time.current.iso8601 } },
           as: :json,
           headers: { "Authorization" => "Bearer invalid-token" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Unauthorized")
      expect(Logister).to have_received(:report_log).with(
        message: "Client ingest rejected",
        level: "warn",
        fingerprint: "client-submission:ingest:invalid_api_key",
        context: hash_including(
          client_submission: hash_including(
            reason: "invalid_api_key",
            status: 401,
            auth: hash_including(
              bearer_present: true,
              token_digest_prefix: Digest::SHA256.hexdigest("invalid-token")[0, 16]
            ),
            payload: hash_including(
              envelope_key: "event",
              event_type: "error",
              message_present: true
            )
          )
        )
      )
    end

    it "accepts X-Api-Key header" do
      expect {
        post api_v1_ingest_events_path,
             params: { event: { event_type: "metric", message: "ping", occurred_at: Time.current.iso8601, context: {} } },
             as: :json,
             headers: { "X-Api-Key" => "test-token-one" }
      }.to change(IngestEvent, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "accepts transaction events and normalizes top-level fields into context" do
      post api_v1_ingest_events_path,
           params: {
             event: {
               event_type: "transaction",
               level: "info",
               message: "POST /checkout",
               duration_ms: 185.2,
               transaction_name: "POST /checkout",
               trace_id: "trace-123",
               request_id: "req-123",
               release: "2026.03.02",
               environment: "production"
             }
           },
           as: :json,
           headers: auth_headers

      expect(response).to have_http_status(:created)
      created = IngestEvent.order(:id).last
      expect(created).to be_transaction
      expect(created.context["duration_ms"]).to eq(185.2)
      expect(created.context["transaction_name"]).to eq("POST /checkout")
      expect(created.context["trace_id"]).to eq("trace-123")
      expect(created.context["request_id"]).to eq("req-123")
      expect(created.context["release"]).to eq("2026.03.02")
    end

    it "accepts CFML-style uppercase event envelopes" do
      post api_v1_ingest_events_path,
           params: {
             EVENT: {
               EVENT_TYPE: "transaction",
               LEVEL: "info",
               MESSAGE: "HEAD /index.cfm",
               FINGERPRINT: "cfml-head-index",
               OCCURRED_AT: "2026-05-21T00:41:19Z",
               CONTEXT: {
                 ENVIRONMENT: "production",
                 SERVICE: "quria",
                 TRANSACTION_NAME: "HEAD /index.cfm",
                 DURATION_MS: 1,
                 TRACE: {
                   TRACEID: "trace-cfml-1",
                   REQUESTID: "trace-cfml-1"
                 }
               }
             }
           },
           as: :json,
           headers: auth_headers

      expect(response).to have_http_status(:created)

      created = IngestEvent.order(:id).last
      expect(created).to be_transaction
      expect(created.message).to eq("HEAD /index.cfm")
      expect(created.context["environment"]).to eq("production")
      expect(created.context["service"]).to eq("quria")
      expect(created.context["transaction_name"]).to eq("HEAD /index.cfm")
      expect(created.context["duration_ms"]).to eq(1)
      expect(created.context.dig("trace", "traceid")).to eq("trace-cfml-1")
    end

    it "returns 400 when the event envelope is missing" do
      post api_v1_ingest_events_path,
           params: { payload: { message: "missing envelope" } },
           as: :json,
           headers: auth_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("event")
      expect(Logister).to have_received(:report_log).with(
        message: "Client ingest rejected",
        level: "warn",
        fingerprint: "client-submission:ingest:missing_event_envelope",
        context: hash_including(
          client_submission: hash_including(
            reason: "missing_event_envelope",
            status: 400,
            payload: hash_including(root_keys: include("payload"))
          )
        )
      )
    end

    it "does not recursively report rejected client-submission monitoring events" do
      post api_v1_ingest_events_path,
           params: {
             event: {
               event_type: "log",
               message: "Client ingest rejected",
               context: {
                 client_submission: {
                   reason: "invalid_api_key"
                 }
               }
             }
           },
           as: :json,
           headers: { "Authorization" => "Bearer invalid-token" }

      expect(response).to have_http_status(:unauthorized)
      expect(Logister).not_to have_received(:report_log)
    end

    it "returns 422 when event is invalid" do
      post api_v1_ingest_events_path,
           params: { event: { event_type: "error" } }, # missing message, occurred_at
           as: :json,
           headers: auth_headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body["errors"]).to be_present
      expect(Logister).to have_received(:report_log).with(
        message: "Client ingest rejected",
        level: "warn",
        fingerprint: "client-submission:ingest:invalid_event",
        context: hash_including(
          client_submission: hash_including(
            reason: "invalid_event",
            status: 422,
            project: hash_including(slug: api_keys(:one).project.slug),
            errors: include("Message can't be blank")
          )
        )
      )
    end
  end
end
