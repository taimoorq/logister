require "rails_helper"

RSpec.describe ProjectConnectionReport do
  let(:user) { create(:user) }
  let(:app) { create(:project, :ios, user:, cross_project_correlations_enabled: true) }
  let(:backend) { create(:project, user:, cross_project_correlations_enabled: true) }
  before do
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    ProjectLink.connect!(actor: user, source: app, target: backend, environment_pairs: [ { "source" => "production", "target" => "live" } ])
  end

  def report(**params)
    described_class.new(principal: user, project: app, params:).call
  end

  it "batches related evidence, preserves release identities and counts request spans separately" do
    create(:ingest_event, :grouped, project: app, context: { trace_id: "shared", environment: "production", app: { version_name: "2", version_code: "12" }, session: { id: "session" }, installation: { id_hash: "installation" }, release: "app-2" })
    create(:trace_span, project: app, trace_id: "shared", span_id: "client", kind: "http", status: "error", context: { environment: "production", release: "app-2" })
    create(:trace_span, project: backend, trace_id: "shared", parent_span_id: "client", status: "error", context: { environment: "live", release: "api-8" })
    create(:ingest_event, :grouped, project: backend, context: { trace_id: "shared", environment: "live", release: "api-8" })
    result = report
    expect(result[:matched_anchor_count]).to eq(2)
    expect(result[:metrics].sum { |row| row[:requests] }).to eq(2)
    expect(result[:impact].first).to include(installations: 1, sessions: 1, matched_errors: 1)
    expect(result[:pairs].any? { |pair| pair[:evidence] == "parent_span" }).to be(true)
    expect(result[:pairs].map { |pair| pair[:peer][:release] }.uniq).to eq([ "api-8" ])
    expect(result.to_json).not_to include('"installation_hash"', '"session_hash"')
  end

  it "filters app builds before sampling and excludes wrong environments, contradictory IDs and coarse diagnostics" do
    create(:ingest_event, project: app, context: { trace_id: "shared", request_id: "same", app: { version_code: "12" } })
    create(:ingest_event, project: app, context: { trace_id: "other", app: { version_code: "13" } })
    create(:ingest_event, project: backend, context: { trace_id: "shared", environment: "production" })
    create(:ingest_event, project: backend, context: { trace_id: "wrong", request_id: "same", environment: "live" })
    create(:ingest_event, project: backend, context: { trace_id: "shared", environment: "live", telemetry_evidence: { time: { precision: "reporting_interval" } } })
    result = report(build_number: "12")
    expect(result[:anchor_count]).to eq(1)
    expect(result[:pairs]).to be_empty
  end

  it "does not reveal a disconnected peer or allow a selected inaccessible project" do
    create(:ingest_event, project: app, context: { trace_id: "shared" })
    create(:ingest_event, project: backend, context: { trace_id: "shared", environment: "live" })
    count = 0
    allow(ProjectCorrelationPolicy).to receive(:projects).and_wrap_original do |original, **args|
      count += 1
      ProjectLink.delete_all if count == 2
      original.call(**args)
    end
    result = report
    expect(result[:pairs]).to be_empty
    expect(result.to_json).not_to include(backend.uuid, backend.name)
    expect { report(connected_project: backend.uuid) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "limits windows and marks row truncation" do
    expect { report(from: 8.days.ago.iso8601) }.to raise_error(described_class::InvalidScope)
    stub_const("ProjectConnectionReport::LIMIT", 1)
    2.times { create(:ingest_event, project: app, context: { trace_id: "shared" }) }
    expect(report).to include(truncated: true, partial: true, anchor_count: 1)
  end
  it "keeps database query count constant as the matched population grows" do
    create(:trace_span, project: app, trace_id: "shared")
    create(:trace_span, project: backend, trace_id: "shared", context: { environment: "live" })
    report # Warm model metadata outside the measured work.
    queries = lambda do
      statements = []
      ActiveSupport::Notifications.subscribed(->(*args) { payload = args.last; statements << payload[:sql] if payload[:sql].start_with?("SELECT") && payload[:name] != "SCHEMA" }, "sql.active_record") { report }
      statements.size
    end
    baseline = queries.call
    12.times do |index|
      create(:trace_span, project: app, trace_id: "shared", context: { release: "app-#{index}" })
      create(:trace_span, project: backend, trace_id: "shared", context: { environment: "live", release: "api-#{index}" })
    end
    # At most one batched deployment query per project is added.
    expect(queries.call).to be <= baseline + 2
  end

  it "caps pairs and preserves explicit partial evidence in a bounded download" do
    stub_const("ProjectConnectionReport::PAIR_LIMIT", 2)
    3.times { create(:trace_span, project: app, trace_id: "shared") }
    3.times { create(:trace_span, project: backend, trace_id: "shared", context: { environment: "live" }) }
    result = report
    expect(result[:pairs].size).to eq(2)
    expect(result).to include(partial: true, truncated: true)
    expect(result.to_json.bytesize).to be < 1.megabyte
  end

  it "filters peer builds and compares observed errors around the selected deployment" do
    at = 1.hour.ago
    deployment = app.deployments.create!(environment: "production", release: "app-2", deployed_at: at, repository_full_name: "example/app", commit_sha: "a" * 40)
    [ -60, 60 ].each do |offset|
      create(:ingest_event, project: app, occurred_at: at + offset, context: { trace_id: "shared" })
      create(:ingest_event, project: backend, occurred_at: at + offset, context: { trace_id: "shared", environment: "live", app: { version_code: "17" } })
    end
    create(:ingest_event, project: backend, occurred_at: at, context: { trace_id: "shared", environment: "live", app: { version_code: "18" } })
    result = report(deployment_uuid: deployment.uuid, peer_build_number: "17")
    expect(result[:pairs].map { |pair| pair[:peer][:build_number] }.uniq).to eq([ "17" ])
    expect(result[:comparison][:projects]).to all(include(before_errors: 1, after_errors: 1))
    expect(result[:comparison][:before_seconds]).to eq(12.hours)
  end
end
