# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::CheckIns", type: :request do
  describe "POST /api/v1/check_ins" do
    before do
      allow(Logister).to receive(:report_log).and_return(true)
    end

    let(:auth_headers) { { "Authorization" => "Bearer test-token-one", "User-Agent" => "LogisterTest/1.0" } }

    it "creates a check_in event and defers monitor derivation to the projector" do
      expect {
        post api_v1_check_ins_path,
             params: {
               check_in: {
                 slug: "daily-billing-job",
                 status: "ok",
                 environment: "production",
                 expected_interval_seconds: 600,
                 release: "2026.03.02"
               }
             },
             as: :json,
             headers: auth_headers
      }.to change(IngestEvent, :count).by(1)

      expect(response).to have_http_status(:created)
      event = IngestEvent.find_by!(uuid: response.parsed_body["id"])
      expect(event).to be_check_in
      expect(event.context["check_in_slug"]).to eq("daily-billing-job")
      expect(event.context["expected_interval_seconds"]).to eq(600)
      expect(CheckInMonitor.find_by(project_id: api_keys(:one).project_id, slug: "daily-billing-job")).to be_nil
      delivery = outbox_for(event).telemetry_deliveries.find_by!(destination: "check_in_monitor")
      expect(delivery).to be_pending
      expect(enqueued_jobs.map { |job| job.fetch(:job) }).to include(TelemetryProjectorJob)

      expect { project_derived_intents!(event) }.to change(CheckInMonitor, :count).by(1)
      monitor = CheckInMonitor.find_by!(project_id: api_keys(:one).project_id, slug: "daily-billing-job")
      expect(monitor).to be_present
      expect(monitor.last_status).to eq("ok")
    end

    it "accepts a client check-in UUID idempotently and repairs the same monitor intent" do
      uuid = "cccccccc-dddd-eeee-ffff-aaaaaaaaaaaa"
      payload = {
        check_in: {
          uuid: uuid,
          slug: "daily-billing-job",
          status: "ok",
          expected_interval_seconds: 600
        }
      }

      expect {
        post api_v1_check_ins_path, params: payload, as: :json, headers: auth_headers
      }.to change(IngestEvent, :count).by(1)
      event = IngestEvent.find_by!(uuid: uuid)
      project_derived_intents!(event)

      expect {
        post api_v1_check_ins_path, params: payload, as: :json, headers: auth_headers
      }.not_to change(IngestEvent, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("id" => uuid, "duplicate" => true, "status" => "accepted")
      expect(outbox_for(event).telemetry_deliveries.where(destination: "check_in_monitor").count).to eq(1)
      expect(CheckInMonitor.where(project: event.project, slug: "daily-billing-job").count).to eq(1)
    end

    it "accepts uppercase check-in envelopes" do
      expect {
        post api_v1_check_ins_path,
             params: {
               CHECK_IN: {
                 SLUG: "hourly-import",
                 STATUS: "ok",
                 ENVIRONMENT: "production",
                 EXPECTED_INTERVAL_SECONDS: 900
               }
             },
             as: :json,
             headers: auth_headers
      }.to change(IngestEvent, :count).by(1)

      expect(response).to have_http_status(:created)
      event = IngestEvent.find_by!(uuid: response.parsed_body["id"])
      expect(event).to be_check_in
      expect(event.context["check_in_slug"]).to eq("hourly-import")
      expect(event.context["expected_interval_seconds"]).to eq(900)
    end

    it "rate limits accepted check-ins per API key and endpoint" do
      with_public_api_rate_limits(requests: 1) do
        expect {
          post api_v1_check_ins_path,
               params: {
                 check_in: {
                   slug: "daily-billing-job",
                   status: "ok",
                   expected_interval_seconds: 600
                 }
               },
               as: :json,
               headers: auth_headers
        }.to change(IngestEvent, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(response.headers["X-RateLimit-Limit"]).to eq("1")

        expect {
          post api_v1_check_ins_path,
               params: {
                 check_in: {
                   slug: "daily-billing-job",
                   status: "ok",
                   expected_interval_seconds: 600
                 }
               },
               as: :json,
               headers: auth_headers
        }.not_to change(IngestEvent, :count)

        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body["error"]).to eq("Rate limit exceeded")
        expect(response.headers["Retry-After"]).to be_present
      end
    end

    it "reports unauthorized check-in submissions" do
      post api_v1_check_ins_path,
           params: { check_in: { slug: "daily-billing-job" } },
           as: :json,
           headers: { "Authorization" => "Bearer invalid-token" }

      expect(response).to have_http_status(:unauthorized)
      expect(Logister).to have_received(:report_log).with(
        message: "Client check_in rejected",
        level: "warn",
        fingerprint: "client-submission:check_in:invalid_api_key",
        context: hash_including(
          client_submission: hash_including(
            reason: "invalid_api_key",
            status: 401,
            auth: hash_including(token_digest_prefix: Digest::SHA256.hexdigest("invalid-token")[0, 16])
          )
        )
      )
    end

    it "returns 400 and reports when the check-in envelope is missing" do
      post api_v1_check_ins_path,
           params: { payload: { slug: "daily-billing-job" } },
           as: :json,
           headers: auth_headers

      expect(response).to have_http_status(:bad_request)
      expect(Logister).to have_received(:report_log).with(
        message: "Client check_in rejected",
        level: "warn",
        fingerprint: "client-submission:check_in:missing_check_in_envelope",
        context: hash_including(
          client_submission: hash_including(
            reason: "missing_check_in_envelope",
            status: 400,
            payload: hash_including(root_keys: include("payload"))
          )
        )
      )
    end
  end

  def outbox_for(record)
    TelemetryOutboxEvent.find_by!(record_type: "IngestEvent", record_id: record.id)
  end

  def project_derived_intents!(record)
    Logister::TelemetryProjector.new.project_synchronously!(outbox_for(record))
  end
end
