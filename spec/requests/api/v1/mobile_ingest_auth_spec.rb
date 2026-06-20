# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mobile ingest authentication", type: :request do
  before do
    allow(Logister).to receive(:report_log).and_return(true)
  end

  let(:project) { create(:project, :android, user: users(:one)) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }
  let(:mobile_token) do
    create(
      :mobile_ingest_token,
      project: project,
      api_key: api_key,
      service: "com.example.app",
      environment: "production",
      release: "1.4.0+42",
      session_id: "session-123"
    )
  end
  let(:mobile_headers) { { "Authorization" => "Bearer #{mobile_token.plain_token}" } }

  it "accepts ingest events with a mobile token and injects bound context" do
    expect {
      post api_v1_ingest_events_path,
           params: {
             event: {
               event_type: "log",
               message: "Checkout opened",
               context: {
                 screen_name: "Checkout"
               }
             }
           },
           as: :json,
           headers: mobile_headers
    }.to change(IngestEvent, :count).by(1)

    expect(response).to have_http_status(:created)
    event = IngestEvent.find_by!(uuid: response.parsed_body["id"])
    expect(event.api_key).to eq(api_key)
    expect(event.context).to include(
      "platform" => "android",
      "service" => "com.example.app",
      "environment" => "production",
      "release" => "1.4.0+42",
      "session_id" => "session-123",
      "screen_name" => "Checkout"
    )
    expect(mobile_token.reload.last_used_at).to be_present
    expect(api_key.reload.last_used_at).to be_present
  end

  it "rejects ingest events that conflict with token-bound context" do
    expect {
      post api_v1_ingest_events_path,
           params: {
             event: {
               event_type: "log",
               message: "Checkout opened",
               environment: "staging",
               context: {
                 service: "com.attacker.app"
               }
             }
           },
           as: :json,
           headers: mobile_headers
    }.not_to change(IngestEvent, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["errors"].join).to include("service must match")
  end

  it "rejects event types outside the mobile token scope" do
    scoped_token = create(
      :mobile_ingest_token,
      project: project,
      api_key: api_key,
      allowed_event_types: [ "error" ]
    )

    expect {
      post api_v1_ingest_events_path,
           params: { event: { event_type: "metric", message: "cart.count", context: { value: 3 } } },
           as: :json,
           headers: { "Authorization" => "Bearer #{scoped_token.plain_token}" }
    }.not_to change(IngestEvent, :count)

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["error"]).to eq("Mobile ingest token cannot send this event type")
  end

  it "accepts span payloads only when span is allowed" do
    expect {
      post api_v1_ingest_events_path,
           params: {
             event: {
               event_type: "span",
               message: "GET /checkout",
               trace_id: "trace-123",
               span_id: "span-123",
               kind: "http",
               duration_ms: 42.0,
               context: {}
             }
           },
           as: :json,
           headers: mobile_headers
    }.to change(TraceSpan, :count).by(1)

    expect(response).to have_http_status(:created)
    span = TraceSpan.find_by!(uuid: response.parsed_body["id"])
    expect(span.context).to include(
      "platform" => "android",
      "service" => "com.example.app",
      "environment" => "production"
    )
  end

  it "accepts check-ins with token-bound context" do
    expect {
      post api_v1_check_ins_path,
           params: {
             check_in: {
               slug: "daily-sync",
               status: "ok",
               expected_interval_seconds: 600
             }
           },
           as: :json,
           headers: mobile_headers
    }.to change(IngestEvent, :count).by(1)

    expect(response).to have_http_status(:created)
    event = IngestEvent.find_by!(uuid: response.parsed_body["id"])
    expect(event.context).to include(
      "platform" => "android",
      "service" => "com.example.app",
      "environment" => "production",
      "release" => "1.4.0+42",
      "session_id" => "session-123"
    )
  end

  it "does not allow mobile tokens to write deployments" do
    expect {
      post api_v1_deployments_path,
           params: {
             deployment: {
               release: "1.4.0+42",
               environment: "production",
               repository: "acme/android-app",
               commit_sha: "abcdef1"
             }
           },
           as: :json,
           headers: mobile_headers
    }.not_to change(ProjectDeployment, :count)

    expect(response).to have_http_status(:forbidden)
  end

  it "rejects expired mobile tokens" do
    mobile_token.update_column(:expires_at, 1.minute.ago)

    post api_v1_ingest_events_path,
         params: { event: { event_type: "log", message: "Checkout opened" } },
         as: :json,
         headers: mobile_headers

    expect(response).to have_http_status(:unauthorized)
    expect(Logister).to have_received(:report_log).with(
      message: "Client ingest rejected",
      level: "warn",
      fingerprint: "client-submission:ingest:expired_mobile_ingest_token",
      context: hash_including(
        client_submission: hash_including(
          reason: "expired_mobile_ingest_token",
          mobile_ingest_token: hash_including(uuid: mobile_token.uuid)
        )
      )
    )
  end

  it "rejects revoked mobile tokens" do
    mobile_token.revoke!

    post api_v1_ingest_events_path,
         params: { event: { event_type: "log", message: "Checkout opened" } },
         as: :json,
         headers: mobile_headers

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects mobile tokens whose parent server key has been revoked" do
    mobile_token
    api_key.revoke!

    post api_v1_ingest_events_path,
         params: { event: { event_type: "log", message: "Checkout opened" } },
         as: :json,
         headers: mobile_headers

    expect(response).to have_http_status(:unauthorized)
    expect(Logister).to have_received(:report_log).with(
      message: "Client ingest rejected",
      level: "warn",
      fingerprint: "client-submission:ingest:revoked_api_key",
      context: hash_including(client_submission: hash_including(reason: "revoked_api_key"))
    )
  end

  it "rejects mobile tokens after their project is archived" do
    mobile_token
    project.archive!

    post api_v1_ingest_events_path,
         params: { event: { event_type: "log", message: "Checkout opened" } },
         as: :json,
         headers: mobile_headers

    expect(response).to have_http_status(:unauthorized)
  end
end
