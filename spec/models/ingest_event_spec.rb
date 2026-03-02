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

  describe ".dashboard_error_views" do
    it "returns at most 6 view hashes" do
      events = IngestEvent.where(project: projects(:one), event_type: :error)
                         .includes(:project)
                         .to_a
      views = described_class.dashboard_error_views(events)
      expect(views.size).to be <= 6
      views.each do |v|
        expect(v).to include(:project, :latest_event, :title, :events_count, :trend, :stage)
      end
    end

    it "returns empty array for empty events" do
      expect(described_class.dashboard_error_views([])).to eq([])
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
