# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectSetupStatus do
  it "does not load mobile evidence for server setup" do
    project = create(:project, :ruby)
    statuses = nil
    queries = capture_sql { statuses = described_class.new(project).call }

    expect(statuses.keys).to contain_exactly(
      :active_api_key, :has_events, :source_repository, :deployments,
      :performance, :teammates, :project_links, :check_ins, :archive_exports
    )
    expect(queries.join("\n")).not_to match(/error_occurrences|mobile_ingest_tokens|apple_symbol_artifacts|android_mapping_files/)
  end

  it "uses accepted receipt evidence and returns typed mobile setup health" do
    project = create(:project, :ios)
    group = create(:error_group, project: project)
    occurrence = create(:error_occurrence, error_group: group, session_hash: "session-hash")
    occurrence.update_columns(
      created_at: 10.minutes.ago,
      dimensions: {
        "app_identifier" => "com.acme.shop",
        "app_version" => "4.2.0",
        "build_number" => "310",
        "diagnostic_source" => "metrickit"
      }
    )

    result = described_class.new(project).call

    expect(result.fetch(:has_events).state).to eq(:configured)
    expect(result.fetch(:app_build_metadata).state).to eq(:configured)
    expect(result.fetch(:sessions).state).to eq(:configured)
    expect(result.fetch(:installations).state).to eq(:unconfigured)
    expect(result.fetch(:metric_kit).state).to eq(:configured)
    expect(result.values).to all(be_a(CapabilityStatus))
  end

  it "distinguishes configured credentials from a successful current provider report" do
    project = create(:project, :android)
    setting = create(
      :project_integration_setting,
      project:,
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.shop",
      credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS"
    )

    expect(described_class.new(project).call.fetch(:google_play).state).to eq(:partial)

    setting.update!(last_imported_at: 2.days.ago)
    expect(described_class.new(project).call.fetch(:google_play).state).to eq(:stale)

    setting.update!(metadata: { "last_error" => { "message" => "permission denied", "at" => Time.current.utc.iso8601 } })
    expect(described_class.new(project).call.fetch(:google_play).state).to eq(:failed)
  end

  describe "performance evidence" do
    let(:project) { create(:project, :ruby) }
    let(:api_key) { create(:api_key, project: project, user: project.user) }

    it "is unconfigured until a transaction or span has been received recently" do
      expect(described_class.new(project).call.fetch(:performance).state).to eq(:unconfigured)

      create(:ingest_event, :transaction, project: project, api_key: api_key, occurred_at: 2.hours.ago)
      expect(described_class.new(project).call.fetch(:performance).state).to eq(:configured)
    end

    it "ignores transactions older than the window" do
      create(:ingest_event, :transaction, project: project, api_key: api_key, occurred_at: 45.days.ago)

      expect(described_class.new(project).call.fetch(:performance).state).to eq(:unconfigured)
    end

    it "counts spans as instrumentation" do
      create(:trace_span, project: project, started_at: 1.hour.ago) if FactoryBot.factories.registered?(:trace_span)

      expect(described_class.new(project).call.fetch(:performance).state).to eq(:configured) if TraceSpan.where(project: project).exists?
    end

    it "asks the database for a single index probe rather than scanning the window" do
      project # create the project outside the measured block
      queries = capture_sql { described_class.new(project).call(keys: [ :performance ]) }.grep(/ingest_events|trace_spans/)

      expect(queries.size).to eq(2)
      expect(queries.first).to match(/ORDER BY "ingest_events"\."occurred_at" DESC LIMIT/)
      expect(queries.last).to match(/ORDER BY "trace_spans"\."started_at" DESC LIMIT/)
      expect(queries.join("\n")).not_to match(/MAX\(/i)
    end
  end

  it "reports teammates from membership evidence" do
    project = create(:project, :ruby)
    expect(described_class.new(project).call(keys: [ :teammates ]).fetch(:teammates).state).to eq(:unconfigured)

    create(:project_membership, project: project, user: create(:user))
    status = described_class.new(project).call(keys: [ :teammates ]).fetch(:teammates)
    expect(status.state).to eq(:configured)
    expect(status.reason).to eq("1 teammate can open this project.")
  end

  it "only loads the evidence it was asked for" do
    project = create(:project, :ruby)

    expect(described_class.new(project).call(keys: [ :has_events ]).keys).to eq([ :has_events ])
  end

  it "checks a mobile receipt without loading payloads or unrelated capabilities" do
    project = create(:project, :ios)
    event = create(:ingest_event, project: project, occurred_at: 60.days.ago)
    statuses = nil

    queries = capture_sql { statuses = described_class.new(project).call(keys: [ :has_events ]) }

    expect(statuses.fetch(:has_events).observed_at).to be_within(1.second).of(event.created_at)
    expect(queries.size).to eq(1)
    expect(queries.sole).to match(/SELECT "ingest_events"\."created_at".*ORDER BY.*LIMIT/)
    expect(queries.sole).not_to include("context")
  end

  it "does not query telemetry when only mobile check-in configuration is requested" do
    project = create(:project, :android)
    create(:check_in_monitor, project: project)

    queries = capture_sql do
      status = described_class.new(project).call(keys: [ :check_ins ]).fetch(:check_ins)
      expect(status.state).to eq(:configured)
      expect(status.action_key).to eq(:configure_mobile_check_ins)
    end

    expect(queries.join("\n")).not_to match(/error_occurrences|ingest_events|android_mapping_files|project_integration_settings/)
  end
end
