# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectArchiveInvestigationSearch, type: :model do
  it "finds hot event, hot span, and candidate archive run matches" do
    project = create(:project, user: users(:one))
    api_key = create(:api_key, project: project, user: project.user)
    event = create(
      :ingest_event,
      :log,
      project: project,
      api_key: api_key,
      message: "Checkout archive marker",
      context: { "request_id" => "req-archive-search", "environment" => "production" }
    )
    span = create(
      :trace_span,
      project: project,
      api_key: api_key,
      trace_id: "trace-archive-search",
      name: "GET /checkout",
      context: { "request_id" => "req-archive-search", "environment" => "production" }
    )
    archive = create(
      :telemetry_archive,
      project: project,
      objects: [ { "key" => "telemetry/ingest_events/checkout-marker.jsonl.gz", "rows" => 1, "bytes" => 128 } ]
    )

    search = described_class.new(
      project: project,
      params: {
        "q" => "checkout",
        "request_id" => "req-archive-search"
      }
    )

    expect(search.hot_events).to include(event)
    expect(search.hot_spans).to include(span)
    expect(search.archive_runs).to include(archive)
  end

  it "limits trace-span searches to spans when the span event type is selected" do
    project = create(:project, user: users(:one))
    api_key = create(:api_key, project: project, user: project.user)
    create(:ingest_event, :log, project: project, api_key: api_key, message: "GET /checkout")
    span = create(:trace_span, project: project, api_key: api_key, name: "GET /checkout")

    search = described_class.new(
      project: project,
      params: {
        "q" => "checkout",
        "event_type" => "span"
      }
    )

    expect(search.hot_events).to be_empty
    expect(search.hot_spans).to contain_exactly(span)
  end
end
