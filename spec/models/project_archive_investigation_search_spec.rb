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

  it "finds delayed mobile diagnostics by receipt clock and typed evidence facets" do
    project = create(:project, :ios)
    event = create(
      :ingest_event,
      project: project,
      occurred_at: 5.days.ago,
      created_at: 5.minutes.ago,
      context: {
        "app" => { "version_code" => "42" },
        "distribution" => { "channel" => "TestFlight" },
        "diagnostic" => { "kind" => "hang" },
        "apple_platform" => "iOS",
        "telemetry_evidence" => { "source" => "metrickit" }
      }
    )
    group = create(:error_group, project: project)
    create(
      :error_occurrence,
      error_group: group,
      ingest_event: event,
      occurred_at: event.occurred_at,
      dimensions: { "symbolication_status" => "artifact_matched" }
    )

    search = described_class.new(
      project: project,
      params: {
        "clock" => "receipt",
        "from" => 1.hour.ago.iso8601,
        "source" => "metrickit",
        "diagnostic_kind" => "hang",
        "build_number" => "42",
        "distribution_channel" => "TestFlight",
        "platform" => "iOS",
        "artifact_state" => "artifact_matched"
      }
    )

    expect(search.hot_events).to contain_exactly(event)
    expect(search.clock_label).to eq("Receipt time")
    expect(search.mobile_summary(event)).to include(source: "metrickit", kind: "hang", build: "42", artifact_state: "artifact_matched")

    evidence_clock = described_class.new(project: project, params: search.params.merge("clock" => "evidence"))
    expect(evidence_clock.hot_events).to be_empty
  end
end
