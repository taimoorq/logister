# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectSetupStatus do
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
end
