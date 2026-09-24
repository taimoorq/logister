require "rails_helper"

RSpec.describe ProjectCorrelationsQuery do
  let(:user) { create(:user) }
  let(:mobile) { create(:project, user:, cross_project_correlations_enabled: true) }
  let(:backend) { create(:project, user:, cross_project_correlations_enabled: true) }
  let(:trace) { "4bf92f3577b34da6a3ce929d0e0e4736" }
  let(:client_span) { "00f067aa0ba902b7" }
  let(:anchor) { create(:ingest_event, project: mobile, context: { trace_id: trace, span_id: client_span, request_id: "request-1", environment: "production" }) }

  before do
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    ProjectLink.connect!(actor: user, source: mobile, target: backend, environment_pairs: [ { "source" => "production", "target" => "production" } ])
  end

  def query(**options)
    described_class.call(principal: user, project: mobile, event: anchor, **options)
  end

  it "finds the backend entry span with a remote parent and its error using legacy nested IDs" do
    span = create(:trace_span, project: backend, trace_id: trace, parent_span_id: client_span)
    error = create(:ingest_event, project: backend, context: { request: { traceId: trace }, environment: "production" })
    result = query
    expect(result[:items].map { |item| item[:uuid] }).to contain_exactly(span.uuid, error.uuid)
    expect(result[:items].find { |item| item[:uuid] == span.uuid }[:evidence]).to eq("parent_span")
    expect(result[:coverage].map { |item| item[:signal] }.uniq).to match_array(described_class::SIGNALS)
  end

  it "excludes unrelated environments, conflicting IDs, and contradictory request-ID matches" do
    create(:ingest_event, project: backend, context: { trace_id: trace, environment: "staging" })
    create(:ingest_event, project: backend, context: { trace_id: trace, request: { trace_id: "another" } })
    create(:ingest_event, project: backend, context: { trace_id: trace, request: { trace_id: "another" }, request_id: "request-1" })
    create(:trace_span, project: backend, trace_id: trace, context: { trace_id: "another", request_id: "request-1" })
    create(:ingest_event, project: backend, context: { trace_id: "another", request_id: "request-1" })
    weaker = create(:ingest_event, project: backend, context: { request_id: "request-1" })
    expect(query[:items].map { |row| [ row[:uuid], row[:evidence] ] }).to eq([ [ weaker.uuid, "shared_request_id" ] ])
  end

  it "does not grant access through a link, including a CLI project allowlist" do
    create(:ingest_event, project: backend, context: { trace_id: trace })
    principal = double(accessible_projects: Project.where(id: mobile.id))
    result = described_class.call(principal:, project: mobile, event: anchor)
    expect(result[:items]).to be_empty
    expect(result[:coverage].map { |row| row[:project_uuid] }.uniq).to eq([ mobile.uuid ])
    backend.update!(purge_requested_at: Time.current)
    expect(query[:items]).to be_empty
  end

  it "does not link aggregate mobile diagnostics or invent IDs" do
    anchor.update!(context: { trace_id: trace, telemetry_evidence: { time: { precision: "reporting_interval" } } })
    expect(query[:reason]).to include("no unambiguous request identifiers")
    expect(query[:coverage]).to be_empty
  end

  it "enforces the window bound" do
    expect { query(from: 2.days.ago.iso8601, to: Time.current.iso8601) }.to raise_error(described_class::InvalidRange)
  end
  it "removes records if environment mappings change during a read" do
    create(:ingest_event, project: backend, context: { trace_id: trace, environment: "production" })
    count = 0
    allow(ProjectCorrelationPolicy).to receive(:projects).and_wrap_original do |original, **args|
      count += 1
      ProjectLink.last.update!(environment_pairs: [ { "source" => "production", "target" => "staging" } ]) if count == 2
      original.call(**args)
    end
    expect(query[:items]).to be_empty
  end

  it "reports bounded and incomplete results without claiming no related records" do
    stub_const("ProjectCorrelationsQuery::LIMIT", 1)
    3.times { create(:ingest_event, project: backend, context: { trace_id: trace }) }
    result = query
    expect(result[:items].size).to eq(1)
    expect(result).to include(truncated: true, partial: true)
  end
end
