# frozen_string_literal: true

require "rails_helper"

RSpec.describe JsonTextQuerying do
  let(:project) { create(:project) }

  it "matches legacy numeric and boolean values as well as strings within the project" do
    events = [ 35, "35", true, "true", "035", nil ].map do |value|
      create(:ingest_event, project:, context: { "trace" => { "traceId" => value } })
    end
    create(:ingest_event, context: { "trace" => { "traceId" => 35 } })
    scope = project.ingest_events

    expect(scope.where_json_text(:context, paths: [ %w[trace traceId] ], value: "35").ids).to match_array(events.first(2).map(&:id))
    expect(scope.where_json_text(:context, paths: [ %w[trace traceId] ], value: "true").ids).to match_array(events[2..3].map(&:id))
  end

  it "keeps exact text semantics for structured values and containment supersets" do
    matching = create(:ingest_event, project:, context: { "identifier" => { "a" => 1 } })
    create(:ingest_event, project:, context: { "identifier" => { "a" => 1, "b" => 2 } })
    create(:ingest_event, project:, context: { "identifier" => [ { "a" => 1 } ] })

    expect(project.ingest_events.where_json_text(:context, paths: [ [ "identifier" ] ], value: '{"a": 1}').ids).to eq([ matching.id ])
  end

  it "preserves numeric precision and safely quotes identifiers and JSON paths" do
    event = create(:ingest_event, project:, context: {})
    event.update_columns(context: { "odd'key" => "x'); SELECT 1; --" })
    expect(project.ingest_events.where_json_text(:context, paths: [ [ "odd'key" ] ], value: "x'); SELECT 1; --").ids).to eq([ event.id ])

    IngestEvent.connection.execute(IngestEvent.sanitize_sql_array([
      "UPDATE ingest_events SET context = ?::jsonb WHERE id = ?", '{"identifier": 1234567890.1234567890123456789}', event.id
    ]))
    expect(project.ingest_events.where_json_text(:context, paths: [ [ "identifier" ] ], value: "1234567890.1234567890123456789").ids).to eq([ event.id ])
  end

  it "still finds strings that look like JSON outside PostgreSQL's supported range" do
    [ "1e999999", "1e-999999", '{"a": "\u0000"}' ].each do |value|
      event = create(:ingest_event, project:, context: { "identifier" => value })
      expect(project.ingest_events.where_json_text(:context, paths: [ [ "identifier" ] ], value:).ids).to eq([ event.id ])
    end
  end
end
