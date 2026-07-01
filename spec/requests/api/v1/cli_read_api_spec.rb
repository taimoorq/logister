# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Cli read API", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, user: user, name: "Checkout API", slug: "checkout-api") }
  let(:api_key) { create(:api_key, project: project, user: user) }
  let(:cli_token) do
    create(
      :cli_access_token,
      user: user,
      all_projects: false,
      allowed_project_ids: [ project.id ],
      scopes: CliAccessToken::READ_SCOPES
    )
  end
  let(:headers) { { "Authorization" => "Bearer #{cli_token.plain_token}" } }

  describe "authentication" do
    it "rejects missing CLI credentials" do
      get "/api/v1/cli/projects"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq("error" => "Unauthorized")
    end

    it "does not accept project ingest API keys as read credentials" do
      get "/api/v1/cli/projects", headers: { "Authorization" => "Bearer #{api_key.plain_token}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects requests missing the required scope" do
      limited = create(
        :cli_access_token,
        user: user,
        all_projects: false,
        allowed_project_ids: [ project.id ],
        scopes: [ "projects:read" ]
      )

      get "/api/v1/cli/projects/#{project.uuid}/events", headers: { "Authorization" => "Bearer #{limited.plain_token}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["required_scopes"]).to eq([ "events:read" ])
    end
  end

  describe "projects" do
    it "lists only token-allowed active projects" do
      create(:project, user: user, name: "Disallowed")
      create(:project, :archived, user: user, name: "Archived", slug: "archived")

      get "/api/v1/cli/projects", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["items"].pluck("slug")).to eq([ "checkout-api" ])
    end

    it "looks up a project by slug within the token allowlist" do
      get "/api/v1/cli/projects/checkout-api", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("uuid" => project.uuid, "slug" => "checkout-api")
    end
  end

  describe "project summary" do
    it "returns event and error counts for the project" do
      create(:ingest_event, :log, project: project, api_key: api_key, occurred_at: 30.minutes.ago)
      create(:error_group, :with_occurrence, project: project, api_key: api_key)

      get "/api/v1/cli/projects/#{project.uuid}/summary", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig("project", "uuid")).to eq(project.uuid)
      expect(body.dig("events_by_type", "log")).to eq(1)
      expect(body.dig("errors", "unresolved")).to eq(1)
    end
  end

  describe "events" do
    it "lists filtered events with server-side redacted context" do
      create(
        :ingest_event,
        :log,
        project: project,
        api_key: api_key,
        message: "payment retry",
        context: {
          "environment" => "production",
          "token" => "secret",
          "user" => { "email" => "customer@example.com" },
          "safe" => "kept"
        }
      )
      create(:ingest_event, :metric, project: project, api_key: api_key, message: "queue.depth")

      get "/api/v1/cli/projects/#{project.uuid}/events", params: { type: "log", q: "payment" }, headers: headers

      expect(response).to have_http_status(:ok)
      event = response.parsed_body["items"].sole
      expect(event["message"]).to eq("payment retry")
      expect(event.dig("context", "token")).to eq("[REDACTED]")
      expect(event.dig("context", "user", "email")).to eq("[REDACTED]")
      expect(event.dig("context", "safe")).to eq("kept")
    end

    it "filters transaction events by duration and errored status" do
      create(
        :ingest_event,
        :transaction,
        project: project,
        api_key: api_key,
        message: "GET /fast",
        context: { "transaction_name" => "GET /fast", "duration_ms" => 20.0, "status" => 200 }
      )
      slow_error = create(
        :ingest_event,
        :transaction,
        project: project,
        api_key: api_key,
        message: "POST /checkout",
        context: { "transaction_name" => "POST /checkout", "duration_ms" => 650.5, "status" => 503 }
      )

      get "/api/v1/cli/projects/#{project.uuid}/events",
          params: { type: "transaction", status: "errored", min_duration_ms: "500" },
          headers: headers

      expect(response).to have_http_status(:ok)
      event = response.parsed_body["items"].sole
      expect(event).to include(
        "uuid" => slow_error.uuid,
        "transaction_name" => "POST /checkout",
        "duration_ms" => 650.5,
        "status" => 503
      )
    end
  end

  describe "error groups" do
    it "returns redacted issue detail and AI context" do
      event = create(
        :ingest_event,
        project: project,
        api_key: api_key,
        message: "Checkout failed",
        fingerprint: "checkout-failed",
        context: {
          "request_id" => "req-123",
          "token" => "secret",
          "exception" => {
            "class" => "RuntimeError",
            "message" => "Checkout failed",
            "backtrace" => [ "app/services/checkout.rb:12:in `call`" ],
            "locals" => { "api_key" => "secret" }
          }
        }
      )
      group = create(:error_group, project: project, latest_event: event, fingerprint: "checkout-failed", title: "Checkout failed")
      create(:error_occurrence, error_group: group, ingest_event: event, occurred_at: event.occurred_at)
      event.update!(error_group: group)
      create(:ingest_event, :log, project: project, api_key: api_key, message: "Related", context: { "request_id" => "req-123", "password" => "secret" })

      get "/api/v1/cli/projects/#{project.uuid}/error_groups/#{group.uuid}", params: { related_logs: true }, headers: headers

      expect(response).to have_http_status(:ok)
      detail = response.parsed_body
      expect(detail.dig("error_group", "title")).to eq("Checkout failed")
      expect(detail.dig("related_logs", 0, "context", "password")).to eq("[REDACTED]")

      get "/api/v1/cli/projects/#{project.uuid}/error_groups/#{group.uuid}/context", headers: headers

      expect(response).to have_http_status(:ok)
      context = response.parsed_body
      expect(context["format"]).to eq("logister_ai_context")
      expect(context.dig("latest_event", "context", "token")).to eq("[REDACTED]")
      expect(context.dig("exception", "data", "locals", "api_key")).to eq("[REDACTED]")
    end
  end
end
