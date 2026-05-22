# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectPerformance do
  describe ".request_breakdown" do
    it "builds stacked request timing rows from root and child spans" do
      project = create(:project)
      api_key = create(:api_key, project: project, user: project.user)
      root = create(
        :trace_span,
        project: project,
        api_key: api_key,
        trace_id: "trace-abc",
        span_id: "root",
        kind: "server",
        name: "GET /checkout",
        duration_ms: 300.0,
        context: { "route" => "GET /checkout", "request_id" => "req-abc" }
      )
      create(:trace_span, project: project, api_key: api_key, trace_id: root.trace_id, span_id: "db", parent_span_id: "root", kind: "db", duration_ms: 80.0)
      create(:trace_span, project: project, api_key: api_key, trace_id: root.trace_id, span_id: "render", parent_span_id: "root", kind: "render", duration_ms: 40.0)
      create(:trace_span, project: project, api_key: api_key, trace_id: root.trace_id, span_id: "http", parent_span_id: "root", kind: "http", duration_ms: 30.0)

      payload = described_class.request_breakdown(project, since: 1.hour.ago)
      request = payload.fetch(:requests).first

      expect(request).to include(
        source: "span",
        label: "GET /checkout",
        duration_ms: 300.0,
        trace_id: "trace-abc",
        request_id: "req-abc",
        child_count: 3
      )
      expect(request.fetch(:segments)).to include(
        "app" => 150.0,
        "db" => 80.0,
        "render" => 40.0,
        "http" => 30.0
      )
    end

    it "falls back to transaction timing context when spans are not present" do
      project = create(:project)
      api_key = create(:api_key, project: project, user: project.user)
      create(
        :ingest_event,
        :transaction,
        project: project,
        api_key: api_key,
        context: {
          "transaction_name" => "POST /checkout",
          "duration_ms" => 200.0,
          "timing_breakdown" => { "db" => 30.0, "render" => 20.0 }
        }
      )

      request = described_class.request_breakdown(project, since: 1.hour.ago).fetch(:requests).first

      expect(request).to include(source: "transaction", label: "POST /checkout", duration_ms: 200.0)
      expect(request.fetch(:segments)).to include("app" => 150.0, "db" => 30.0, "render" => 20.0)
    end
  end
end
