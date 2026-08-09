# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Cli v3.5 read API", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, user:, name: "Checkout", slug: "checkout") }
  let(:api_key) { create(:api_key, project:, user:) }
  let(:token) do
    create(
      :cli_access_token,
      user:,
      all_projects: false,
      allowed_project_ids: [ project.id ],
      scopes: CliAccessToken::READ_SCOPES
    )
  end
  let(:headers) { { "Authorization" => "Bearer #{token.plain_token}" } }

  describe "capabilities and session" do
    it "keeps new features disabled by default while advertising session diagnostics" do
      get "/api/v1/cli/capabilities"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("endpoints", "session")).to eq("/api/v1/cli/session")
      expect(response.parsed_body.fetch("features")).to include(
        "traces" => false,
        "monitors" => false,
        "deployments" => false,
        "insights" => false,
        "metrics" => false
      )
      expect(response.parsed_body.dig("auth", "recommended_scopes")).to match_array(CliAccessToken::READ_SCOPES)
    end

    it "returns bounded diagnostics and missing scopes without token secrets" do
      project
      old_scopes = %w[projects:read project_summary:read events:read errors:read ai_context:read]
      old_token = create(:cli_access_token, user:, scopes: old_scopes, all_projects: true)

      get "/api/v1/cli/session", headers: { "Authorization" => "Bearer #{old_token.plain_token}" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig("token", "uuid")).to eq(old_token.uuid)
      expect(body["accessible_project_count"]).to eq(1)
      expect(body["accessible_project_uuids"]).to eq([ project.uuid ])
      expect(body["missing_recommended_scopes"]).to match_array(%w[traces:read monitors:read deployments:read insights:read metrics:read])
      expect(response.body).not_to include(old_token.token_digest)
      expect(response.body).not_to include(old_token.plain_token)
    end

    it "returns actionable required scopes for old tokens" do
      old_token = create(:cli_access_token, user:, scopes: [ "projects:read" ], all_projects: true)

      get "/api/v1/cli/projects/#{project.uuid}/traces", headers: { "Authorization" => "Bearer #{old_token.plain_token}" }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to include(
        "code" => "insufficient_scope",
        "required_scopes" => [ "traces:read" ]
      )
    end

    it "rejects expired and revoked tokens across the new authenticated surface" do
      expired = create(:cli_access_token, user:, scopes: CliAccessToken::READ_SCOPES)
      revoked = create(:cli_access_token, user:, scopes: CliAccessToken::READ_SCOPES)
      expired_raw = expired.plain_token
      revoked_raw = revoked.plain_token
      expired.update_column(:expires_at, 1.minute.ago)
      revoked.revoke!

      get "/api/v1/cli/session", headers: { "Authorization" => "Bearer #{expired_raw}" }
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/cli/projects/#{project.uuid}/metrics/catalog",
          headers: { "Authorization" => "Bearer #{revoked_raw}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "tenant-safe project lookup" do
    it "rejects ambiguous member-visible slugs and neutralizes cross-project identifiers" do
      other_owner = create(:user)
      other = create(:project, user: other_owner, slug: project.slug)
      create(:project_membership, project: other, user:)
      all_projects_token = create(:cli_access_token, user:, all_projects: true, scopes: CliAccessToken::READ_SCOPES)
      other_span = create(:trace_span, project: other)

      get "/api/v1/cli/projects/#{project.slug}", headers: { "Authorization" => "Bearer #{all_projects_token.plain_token}" }
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["code"]).to eq("ambiguous_project")

      get "/api/v1/cli/projects/#{project.uuid}/traces/#{other_span.trace_id}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["code"]).to eq("not_found")
    end

    it "re-evaluates project allowlists, membership loss, and archived visibility" do
      other = create(:project, user:)

      get "/api/v1/cli/projects/#{other.uuid}/monitors", headers: headers
      expect(response).to have_http_status(:not_found)

      shared_owner = create(:user)
      shared = create(:project, user: shared_owner)
      membership = create(:project_membership, project: shared, user:)
      shared_token = create(
        :cli_access_token,
        user:,
        all_projects: false,
        allowed_project_ids: [ shared.id ],
        scopes: CliAccessToken::READ_SCOPES
      )
      membership.destroy!

      get "/api/v1/cli/projects/#{shared.uuid}/deployments",
          headers: { "Authorization" => "Bearer #{shared_token.plain_token}" }
      expect(response).to have_http_status(:not_found)

      project.update!(archived_at: Time.current)
      get "/api/v1/cli/projects", headers: headers
      expect(response.parsed_body["items"].pluck("uuid")).not_to include(project.uuid)

      get "/api/v1/cli/projects", params: { include_archived: true }, headers: headers
      expect(response.parsed_body["items"].pluck("uuid")).to include(project.uuid)
    end
  end

  describe "traces" do
    it "lists filtered roots and returns a bounded, redacted span tree through PostgreSQL fallback" do
      root = create(
        :trace_span,
        project:,
        api_key:,
        trace_id: "trace-checkout",
        span_id: "root",
        duration_ms: 650,
        context: {
          "route" => "POST /checkout",
          "environment" => "production",
          "release" => "2026.08.09",
          "service" => "web",
          "token" => "secret"
        }
      )
      child = create(
        :trace_span,
        project:,
        api_key:,
        trace_id: root.trace_id,
        span_id: "child",
        parent_span_id: root.span_id,
        kind: "db",
        name: "SELECT orders",
        duration_ms: 25,
        context: { "password" => "secret", "safe" => "kept" }
      )

      get "/api/v1/cli/projects/#{project.uuid}/traces",
          params: { environment: "production", service: "web", operation: "POST /checkout", min_duration_ms: 500 },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["items"].sole).to include(
        "uuid" => root.uuid,
        "trace_id" => root.trace_id,
        "operation" => "POST /checkout"
      )
      expect(response.parsed_body.dig("analytics", "source")).to eq("postgresql")

      get "/api/v1/cli/projects/#{project.uuid}/traces/#{root.trace_id}", headers: headers

      expect(response).to have_http_status(:ok)
      spans = response.parsed_body["spans"].index_by { |span| span.fetch("uuid") }
      expect(spans.dig(root.uuid, "context", "token")).to eq("[REDACTED]")
      expect(spans.dig(child.uuid, "context", "password")).to eq("[REDACTED]")
      expect(spans.dig(child.uuid, "context", "safe")).to eq("kept")
    end

    it "uses a filter-bound signed cursor" do
      timestamp = 2.minutes.ago
      3.times { |index| create(:trace_span, project:, api_key:, started_at: timestamp - index.seconds) }

      get "/api/v1/cli/projects/#{project.uuid}/traces", params: { limit: 2 }, headers: headers
      cursor = response.parsed_body["next_cursor"]
      expect(cursor).to be_present

      get "/api/v1/cli/projects/#{project.uuid}/traces", params: { limit: 2, cursor:, status: "error" }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("invalid_cursor")
    end

    it "omits an oversized first-span context and keeps the trace response below one MiB" do
      span = create(
        :trace_span,
        project:,
        api_key:,
        trace_id: "trace-large",
        span_id: "root-large",
        context: { "safe" => "x" * 1_100_000 }
      )

      get "/api/v1/cli/projects/#{project.uuid}/traces/#{span.trace_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body.bytesize).to be < 1.megabyte
      expect(response.parsed_body.dig("spans", 0, "context_truncated")).to be(true)
      expect(response.parsed_body.dig("spans", 0, "context")).to eq({})
      expect(response.parsed_body["truncated"]).to be(true)
    end

    it "caps trace detail at 200 spans and marks the response truncated" do
      now = Time.current - 1
      TraceSpan.insert_all!(Array.new(201) do |index|
        {
          project_id: project.id,
          api_key_id: api_key.id,
          uuid: SecureRandom.uuid,
          trace_id: "trace-wide",
          span_id: "span-#{index}",
          name: "work #{index}",
          kind: "internal",
          status: "ok",
          duration_ms: 1,
          started_at: now + index.fdiv(1_000),
          ended_at: now + (index + 1).fdiv(1_000),
          context: {},
          created_at: now,
          updated_at: now
        }
      end)

      get "/api/v1/cli/projects/#{project.uuid}/traces/trace-wide", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["span_count"]).to eq(200)
      expect(response.parsed_body.fetch("spans").length).to eq(200)
      expect(response.parsed_body["truncated"]).to be(true)
    end
  end

  describe "monitors" do
    it "uses stable UUIDs and one status snapshot for list and detail" do
      ok = create(:check_in_monitor, :with_last_event, project:, api_key:, slug: "billing", last_check_in_at: 1.minute.ago)
      create(:check_in_monitor, :missed, project:, slug: "stale")

      get "/api/v1/cli/projects/#{project.uuid}/monitors", params: { status: "ok" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["items"].sole).to include("uuid" => ok.uuid, "status" => "ok")

      get "/api/v1/cli/projects/#{project.uuid}/monitors/#{ok.uuid}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("uuid" => ok.uuid, "slug" => "billing")
      expect(response.parsed_body).not_to have_key("notification_state")
    end

    it "matches Ruby monitor grace-period truncation for odd intervals" do
      travel_to Time.zone.local(2026, 8, 9, 12, 0, 0) do
        monitor = create(
          :check_in_monitor,
          project:,
          expected_interval_seconds: 101,
          last_check_in_at: 151.5.seconds.ago,
          last_status: "ok"
        )
        expect(monitor.status(at: Time.current)).to eq("missed")

        get "/api/v1/cli/projects/#{project.uuid}/monitors", params: { status: "missed" }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["items"].pluck("uuid")).to include(monitor.uuid)
      end
    end

    it "reports ok, error, missed, and paused status variants from one snapshot" do
      create(:check_in_monitor, project:, slug: "ok")
      create(:check_in_monitor, :errored, project:, slug: "error")
      create(:check_in_monitor, :missed, project:, slug: "missed")
      create(:check_in_monitor, project:, slug: "paused", monitoring_paused_at: 1.minute.ago)

      get "/api/v1/cli/projects/#{project.uuid}/monitors", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["items"].pluck("status")).to contain_exactly("ok", "error", "missed", "paused")
      expect(response.parsed_body["generated_at"]).to be_present
    end
  end

  describe "deployments" do
    it "reuses filters and previous-deployment context without leaking metadata secrets" do
      previous = create(:project_deployment, project:, release: "1.0.0", commit_sha: "abc1234", deployed_at: 2.hours.ago)
      current = create(
        :project_deployment,
        project:,
        project_source_repository: previous.project_source_repository,
        repository_full_name: previous.repository_full_name,
        release: "1.1.0",
        commit_sha: "def5678",
        deployed_at: 1.hour.ago,
        metadata: { "token" => "secret", "safe" => "kept" }
      )

      get "/api/v1/cli/projects/#{project.uuid}/deployments", params: { release: current.release }, headers: headers

      expect(response).to have_http_status(:ok)
      deployment = response.parsed_body["items"].sole
      expect(deployment).to include("uuid" => current.uuid, "release" => "1.1.0")
      expect(deployment.dig("metadata", "token")).to eq("[REDACTED]")
      expect(deployment.dig("metadata", "safe")).to eq("kept")
      expect(deployment.dig("previous_deployment", "uuid")).to eq(previous.uuid)
    end

    it "binds deployment cursors to filters" do
      2.times { |index| create(:project_deployment, project:, release: "release-#{index}", deployed_at: index.hours.ago) }

      get "/api/v1/cli/projects/#{project.uuid}/deployments", params: { limit: 1 }, headers: headers
      cursor = response.parsed_body["next_cursor"]
      expect(cursor).to be_present

      get "/api/v1/cli/projects/#{project.uuid}/deployments",
          params: { limit: 1, cursor:, release: "release-1" },
          headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("invalid_cursor")
    end
  end

  describe "Insights and metrics" do
    before do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    end

    it "filters semantic sensitive attributes and returns exactly one requested metric series" do
      create(
        :ingest_event,
        :metric,
        project:,
        api_key:,
        message: "queue.depth",
        context: { "value" => 7, "tenant" => "acme", "customer_email" => "secret@example.com" },
        occurred_at: 5.minutes.ago
      )

      get "/api/v1/cli/projects/#{project.uuid}/insights", params: { window: "1h", metric: [ "events.total" ] }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key("recent_events")
      expect(response.parsed_body.fetch("attributes").pluck("key")).to include("tenant")
      expect(response.parsed_body.fetch("attributes").pluck("key")).not_to include("customer_email")

      get "/api/v1/cli/projects/#{project.uuid}/metrics/query",
          params: { window: "1h", metric: "metric_value:queue.depth" },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("metric", "key")).to eq("metric_value:queue.depth")
      expect(response.parsed_body.dig("series", "key")).to eq("metric_value:queue.depth")
    end

    it "rejects unknown metrics instead of substituting defaults" do
      get "/api/v1/cli/projects/#{project.uuid}/metrics/query", params: { metric: "missing.metric" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("code" => "invalid_parameter", "parameter" => "metric")
    end

    it "reuses the shared dashboard cache and rejects unknown attributes" do
      allow(ProjectInsights).to receive(:dashboard_for).and_call_original

      2.times do
        get "/api/v1/cli/projects/#{project.uuid}/insights",
            params: { window: "1h", metric: [ "events.total" ] },
            headers: headers
        expect(response).to have_http_status(:ok)
      end
      expect(ProjectInsights).to have_received(:dashboard_for).once

      get "/api/v1/cli/projects/#{project.uuid}/insights",
          params: { window: "1h", attribute: [ "unknown=value" ] },
          headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("code" => "invalid_parameter", "parameter" => "attribute")
    end

    it "rejects semantically sensitive attribute-key variants before catalog lookup" do
      expect(ProjectInsightsCache).not_to receive(:filter_options)

      get "/api/v1/cli/projects/#{project.uuid}/insights",
          params: { window: "1h", attribute: [ "x-api-key=secret" ] },
          headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("code" => "invalid_parameter", "parameter" => "attribute")
    end

    it "preserves repeated metric[] and attribute[] values from the raw query string" do
      create(
        :ingest_event,
        :log,
        project:,
        api_key:,
        context: { "tenant" => "acme", "region" => "us-east-1" },
        occurred_at: 5.minutes.ago
      )
      raw_query = [
        "metric%5B%5D=events.total",
        "metric%5B%5D=logs.count",
        "attribute%5B%5D=tenant%3Dacme",
        "attribute%5B%5D=region%3Dus-east-1"
      ].join("&")

      get "/api/v1/cli/projects/#{project.uuid}/insights?#{raw_query}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("selected_metrics")).to eq(%w[events.total logs.count])
      expect(response.parsed_body.fetch("attribute_filters")).to contain_exactly(
        hash_including("key" => "tenant", "value" => "acme"),
        hash_including("key" => "region", "value" => "us-east-1")
      )
    end
  end

  describe "event list and follow cursors" do
    it "paginates descending and polls late arrivals by created-at plus UUID without same-timestamp loss" do
      travel_to Time.zone.local(2026, 8, 9, 12, 0, 0) do
        create(:ingest_event, :log, project:, api_key:, occurred_at: 1.minute.ago, created_at: 1.second.ago)
        get "/api/v1/cli/projects/#{project.uuid}/events", params: { type: "log" }, headers: headers
        poll_cursor = response.parsed_body["poll_cursor"]
        expect(poll_cursor).to be_present

        late_created_at = 1.second.from_now
        first = create(:ingest_event, :log, project:, api_key:, occurred_at: 10.minutes.ago, created_at: late_created_at)
        second = create(:ingest_event, :log, project:, api_key:, occurred_at: 9.minutes.ago, created_at: late_created_at)

        get "/api/v1/cli/projects/#{project.uuid}/events",
            params: { type: "log", after_cursor: poll_cursor },
            headers: headers

        expect(response).to have_http_status(:ok)
        expected = [ first, second ].sort_by(&:uuid).map(&:uuid)
        expect(response.parsed_body["items"].pluck("uuid")).to eq(expected)
        advanced = response.parsed_body["poll_cursor"]

        get "/api/v1/cli/projects/#{project.uuid}/events",
            params: { type: "log", after_cursor: advanced },
            headers: headers
        expect(response.parsed_body["items"]).to be_empty
        expect(response.parsed_body["poll_cursor"]).to eq(advanced)
      end
    end

    it "does not lose an event inserted after the initial rows query completes" do
      create(:ingest_event, :log, project:, api_key:, occurred_at: 1.minute.ago, created_at: 1.second.ago)
      inserted = nil
      interleaved = false
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        sql = payload[:sql].to_s
        next if interleaved
        next unless sql.include?('ORDER BY "ingest_events"."occurred_at" DESC, "ingest_events"."uuid" DESC')

        interleaved = true
        inserted = create(
          :ingest_event,
          :log,
          project:,
          api_key:,
          message: "interleaved",
          occurred_at: 30.seconds.ago,
          created_at: Time.current
        )
      end

      begin
        get "/api/v1/cli/projects/#{project.uuid}/events", params: { type: "log" }, headers: headers
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(interleaved).to be(true)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("items").pluck("uuid")).not_to include(inserted.uuid)
      poll_cursor = response.parsed_body.fetch("poll_cursor")

      get "/api/v1/cli/projects/#{project.uuid}/events",
          params: { type: "log", after_cursor: poll_cursor },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("items").pluck("uuid")).to include(inserted.uuid)
    end

    it "bounds explicit list context and rejects oversized cursors before verification" do
      event = create(
        :ingest_event,
        :log,
        project:,
        api_key:,
        message: "large context",
        context: { "safe" => "x" * 1_100_000 }
      )

      get "/api/v1/cli/projects/#{project.uuid}/events",
          params: { include_context: true, limit: 1 },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body.bytesize).to be < 1.megabyte
      expect(response.parsed_body.dig("items", 0)).to include(
        "uuid" => event.uuid,
        "context_truncated" => true
      )
      expect(response.parsed_body.dig("items", 0, "context")).to eq({})

      get "/api/v1/cli/projects/#{project.uuid}/events",
          params: { cursor: "x" * (Logister::CliCursor::MAX_BYTES + 1) },
          headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("invalid_cursor")
    end

    it "rejects invalid ranges, limits, searches, and legacy issue cursors without broadening" do
      get "/api/v1/cli/projects/#{project.uuid}/events",
          params: { since: "91d" },
          headers: headers
      expect(response).to have_http_status(:unprocessable_content)

      get "/api/v1/cli/projects/#{project.uuid}/events",
          params: { limit: 101 },
          headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("code" => "invalid_parameter", "parameter" => "limit")

      get "/api/v1/cli/projects/#{project.uuid}/events",
          params: { q: "x" * 201 },
          headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("code" => "invalid_parameter", "parameter" => "q")

      get "/api/v1/cli/projects/#{project.uuid}/error_groups",
          params: { cursor: "x" * (Logister::CliCursor::MAX_BYTES + 1) },
          headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("invalid_cursor")
    end
  end
end
