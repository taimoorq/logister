require "rails_helper"

RSpec.describe "Correlation PostgreSQL / ClickHouse parity" do
  # Explicit disposable endpoint only; never use the application's configured server.
  it "executes canonical matching and deduplicated occurrence queries on ClickHouse" do
    skip "Set LOGISTER_TEST_CLICKHOUSE_URL to a disposable schema-v2 ClickHouse" unless ENV["LOGISTER_TEST_CLICKHOUSE_URL"]
    config = Rails.configuration.x.logister.dup
    config.clickhouse_url = ENV.fetch("LOGISTER_TEST_CLICKHOUSE_URL")
    config.clickhouse_username = "default"
    config.clickhouse_password = ""
    client = Logister::ClickhouseClient.new(config:, force_enabled: true)
    user = create(:user)
    project = create(:project, user:, cross_project_correlations_enabled: true)
    trace = SecureRandom.hex(16)
    event = create(:ingest_event, project:, context: { trace_id: trace, request: { traceId: trace }, environment: "production" })
    other = create(:ingest_event, project:, context: { request: { traceId: trace }, environment: "production" })
    query = ProjectCorrelationsQuery.new(principal: user, project:, event:)
    attributes = Logister::EventIngestor.new(event: other, clickhouse_client: client).attributes
    # Replay a logical event; product reads must return it exactly once.
    client.insert_event!(attributes)
    client.insert_event!(attributes.merge(projection_version: attributes[:projection_version] + 1))
    postgres = query.send(:postgres_rows, project, [ "production" ], "error").reject { |row| row["uuid"] == event.uuid }
    clickhouse = query.send(:clickhouse_rows, client, project, [ "production" ], "error")
    expect(clickhouse.map { |row| row.slice("uuid", "trace_id") }).to eq(postgres.map { |row| row.slice("uuid", "trace_id") })

    span = create(:trace_span, project:, trace_id: trace, parent_span_id: "remote-parent", context: { environment: "production", request: { id: "request-1" } })
    client.insert_span!(Logister::SpanIngestor.new(span:, clickhouse_client: client).attributes)
    pg_spans = query.send(:postgres_rows, project, [ "production" ], "span")
    ch_spans = query.send(:clickhouse_rows, client, project, [ "production" ], "span")
    expect(ch_spans.map { |row| row.slice("uuid", "trace_id", "span_id", "parent_span_id", "request_id") }).to eq(pg_spans.map { |row| row.slice("uuid", "trace_id", "span_id", "parent_span_id", "request_id") })
    performance = Logister::ClickhousePerformanceQuery.new(project:, since: 1.hour.ago, to: 1.hour.from_now, limit: 50, client:).call
    expect(performance[:root_rows].map { |row| row.fetch("span_id") }).to include(span.uuid)

    [ { trace_id: 123, trace: { id: "valid" } }, { trace_id: "", traceId: "old" }, { trace_id: "x", traceId: "y" }, { trace_id: "x" * 129 } ].each do |context|
      sql = "SELECT #{CorrelationContext.clickhouse('trace_id', matchable: true)} AS value FROM (SELECT #{query.send(:quote, context.to_json)} AS context_json)"
      expect(client.select_rows!(sql).first.fetch("value").presence).to eq(CorrelationContext.new(context).matchable("trace_id"))
    end
  ensure
    client&.close
  end
end
