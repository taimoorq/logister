# frozen_string_literal: true

require "rails_helper"

RSpec.describe IngestEvent, type: :model do
  describe "associations" do
    it "belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end

    it "belongs to api_key" do
      expect(described_class.reflect_on_association(:api_key).macro).to eq(:belongs_to)
    end

    it "belongs to error_group optional" do
      a = described_class.reflect_on_association(:error_group)
      expect(a.macro).to eq(:belongs_to)
      expect(a.options[:optional]).to be true
    end

    it "has one error_occurrence dependent destroy" do
      a = described_class.reflect_on_association(:error_occurrence)
      expect(a.macro).to eq(:has_one)
      expect(a.options[:dependent]).to eq(:destroy)
    end
  end

  describe "enums" do
    it "defines event_type error, metric, transaction, log and check_in" do
      expect(ingest_events(:one)).to be_error
      expect(ingest_events(:two)).to be_metric
      expect(described_class.event_types.keys).to include("transaction", "log", "check_in")
    end
  end

  describe "validations" do
    it "validates presence of message and occurred_at" do
      event = IngestEvent.new(project: projects(:one), api_key: api_keys(:one), event_type: :error)
      expect(event).not_to be_valid
      expect(event.errors[:message]).to be_present
      expect(event.errors[:occurred_at]).to be_present
    end
  end

  describe "callbacks" do
    it "assigns uuid before validation" do
      event = IngestEvent.new(
        project: projects(:one),
        api_key: api_keys(:one),
        event_type: :error,
        message: "Test",
        occurred_at: Time.current
      )
      event.valid?
      expect(event.uuid).to be_present
    end
  end

  describe "#to_param" do
    it "returns uuid" do
      expect(ingest_events(:one).to_param).to eq(ingest_events(:one).uuid)
    end
  end

  describe ".db_queries" do
    it "returns only metric events with message db.query" do
      expect(ingest_events(:three)).to be_metric
      expect(ingest_events(:three).message).to eq("db.query")
      expect(described_class.db_queries).to include(ingest_events(:three))
      expect(described_class.db_queries).not_to include(ingest_events(:one))
    end
  end

  describe ".recent_db_queries" do
    it "scopes by since and limit" do
      scope = described_class.where(project: projects(:one)).recent_db_queries(1.day.ago, 10)
      expect(scope.limit_value).to eq(10)
    end
  end

  describe ".duration_ms" do
    it "returns 0 for nil" do
      expect(described_class.duration_ms(nil)).to eq(0.0)
    end

    it "extracts duration_ms from context hash" do
      event = Struct.new(:context).new({ "duration_ms" => 42.5 })
      expect(described_class.duration_ms(event)).to eq(42.5)
    end

    it "accepts symbol key" do
      event = Struct.new(:context).new({ duration_ms: 10.0 })
      expect(described_class.duration_ms(event)).to eq(10.0)
    end

    it "falls back to camelCase duration keys" do
      event = Struct.new(:context).new({ "durationMs" => 15.5 })
      expect(described_class.duration_ms(event)).to eq(15.5)
    end
  end

  describe "context helpers" do
    it "extracts environment with a default fallback" do
      event = Struct.new(:context).new({ "environment" => "staging" })
      missing = Struct.new(:context).new({})

      expect(described_class.environment(event)).to eq("staging")
      expect(described_class.environment(missing, "production")).to eq("production")
    end

    it "extracts release and transaction names from mixed key styles" do
      event = Struct.new(:context).new({ release: "2026.04.17", "transactionName" => "POST /checkout" })

      expect(described_class.release(event)).to eq("2026.04.17")
      expect(described_class.transaction_name(event)).to eq("POST /checkout")
    end

    it "extracts nested trace and request identifiers" do
      event = Struct.new(:context).new({ "trace" => { "traceId" => "trace-123", "requestId" => "req-456" } })

      expect(described_class.trace_id(event)).to eq("trace-123")
      expect(described_class.request_id(event)).to eq("req-456")
    end

    it "extracts session and user identifiers from fallback keys" do
      event = Struct.new(:context).new({ "sessionId" => "session-789", "user" => { "id" => "user-42" } })

      expect(described_class.session_id(event)).to eq("session-789")
      expect(described_class.user_identifier(event)).to eq("user-42")
    end
  end

  describe ".db_stats_from_events" do
    it "returns zero stats for empty list" do
      expect(described_class.db_stats_from_events([])).to eq(
        count: 0, avg_ms: 0.0, p95_ms: 0.0
      )
    end

    it "computes count, avg_ms, p95_ms from event contexts" do
      event_struct = Struct.new(:context)
      events = [
        event_struct.new({ duration_ms: 10.0 }),
        event_struct.new({ duration_ms: 20.0 }),
        event_struct.new({ duration_ms: 30.0 })
      ]
      stats = described_class.db_stats_from_events(events)
      expect(stats[:count]).to eq(3)
      expect(stats[:avg_ms]).to eq(20.0)
      expect(stats[:p95_ms]).to eq(30.0)
    end
  end

  describe ".released_error_groups" do
    it "returns release summaries with grouped event and issue counts" do
      user = create(:user)
      project = create(:project, user: user)
      api_key = create(:api_key, user: user, project: project)

      create(:ingest_event,
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "checkout failed",
        occurred_at: 30.minutes.ago,
        context: { "release" => "2026.04.17", "environment" => "production" })
      create(:ingest_event,
        project: project,
        api_key: api_key,
        event_type: :log,
        message: "checkout info",
        occurred_at: 10.minutes.ago,
        context: { "release" => "2026.04.17", "environment" => "production" })
      ErrorGroup.create!(
        project: project,
        fingerprint: "introduced-checkout-failure",
        title: "Checkout failed",
        status: :unresolved,
        introduced_in_release: "2026.04.17"
      )
      ErrorGroup.create!(
        project: project,
        fingerprint: "regressed-checkout-failure",
        title: "Checkout failed again",
        status: :unresolved,
        regressed_in_release: "2026.04.17"
      )

      releases = described_class.released_error_groups(project, lookback: 2.days, limit: 6)

      expect(releases.first).to include(
        release: "2026.04.17",
        total_events: 2,
        error_events: 1,
        introduced_issues: 1,
        regressed_issues: 1
      )
    end
  end

  describe ".dashboard_error_views" do
    it "returns at most 6 view hashes" do
      events = IngestEvent.where(project: projects(:one), event_type: :error)
                         .includes(:project)
                         .to_a
      views = described_class.dashboard_error_views(events)
      expect(views.size).to be <= 6
      views.each do |v|
        expect(v).to include(:project, :latest_event, :events_count, :error_views)
      end
    end

    it "returns empty array for empty events" do
      expect(described_class.dashboard_error_views([])).to eq([])
    end

    it "returns one dashboard entry per project with grouped errors sorted newest first" do
      user = create(:user)
      recent_project = create(:project, user: user, name: "Recent Project")
      older_project = create(:project, user: user, name: "Older Project")
      recent_key = create(:api_key, user: user, project: recent_project)
      older_key = create(:api_key, user: user, project: older_project)

      newest_group_latest = create(
        :ingest_event,
        project: recent_project,
        api_key: recent_key,
        fingerprint: "checkout-failed",
        message: "Checkout failed",
        occurred_at: 15.minutes.ago
      )
      newest_group_older = create(
        :ingest_event,
        project: recent_project,
        api_key: recent_key,
        fingerprint: "checkout-failed",
        message: "Checkout failed",
        occurred_at: 2.hours.ago
      )
      older_group_latest = create(
        :ingest_event,
        project: recent_project,
        api_key: recent_key,
        fingerprint: "billing-timeout",
        message: "Billing timeout",
        occurred_at: 45.minutes.ago
      )
      older_project_event = create(
        :ingest_event,
        project: older_project,
        api_key: older_key,
        fingerprint: "job-failed",
        message: "Job failed",
        occurred_at: 3.hours.ago
      )

      views = described_class.dashboard_error_views([
        newest_group_latest,
        newest_group_older,
        older_group_latest,
        older_project_event
      ])

      expect(views.map { |view| view[:project] }).to eq([ recent_project, older_project ])
      expect(views.first[:events_count]).to eq(3)
      expect(views.first[:error_views].size).to eq(2)
      expect(views.first[:error_views].map { |view| view[:title] }).to eq([ "Checkout failed", "Billing timeout" ])
      expect(views.first[:error_views].map { |view| view[:latest_event] }).to eq([ newest_group_latest, older_group_latest ])
    end
  end

  describe ".related_logs" do
    it "matches logs by trace and request identifiers" do
      project = projects(:one)
      api_key = api_keys(:one)
      error_event = described_class.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        level: "error",
        message: "Checkout failed",
        occurred_at: Time.current,
        context: { "trace_id" => "trace-123", "request_id" => "req-abc" }
      )
      related_log = described_class.create!(
        project: project,
        api_key: api_key,
        event_type: :log,
        level: "info",
        message: "checkout step",
        occurred_at: Time.current,
        context: { "trace_id" => "trace-123" }
      )

      results = described_class.related_logs(project: project, event: error_event)
      expect(results).to include(related_log)
    end
  end
end
