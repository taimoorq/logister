# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectMobileDistributionSnapshot do
  it "keeps Google Play fetch time, source window, and population separate" do
    project = create(:project, :android)
    fetched_at = 10.minutes.ago
    create(
      :project_integration_setting,
      project:,
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.shop",
      credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS",
      last_imported_at: fetched_at,
      metadata: {
        "reporting" => {
          "fetched_at" => fetched_at.utc.iso8601,
          "window" => { "start" => "2026-07-12", "end" => "2026-08-09" },
          "release_filter_options" => { "tracks" => [ { "servingReleases" => [ { "versionCodes" => [ "42" ] } ] } ] },
          "crash_rates" => { "rows" => [ {} ] },
          "anr_rates" => { "rows" => [ {}, {} ] }
        }
      }
    )

    snapshot = described_class.new(project).call

    expect(snapshot.status.state).to eq(:configured)
    expect(snapshot.report_start).to eq(Date.new(2026, 7, 12))
    expect(snapshot.report_end).to eq(Date.new(2026, 8, 9))
    expect(snapshot.release_count).to eq(1)
    expect(snapshot.metric_row_count).to eq(3)
    expect(snapshot.population_note).to include("eligible Play population")
  end

  it "reports configured Apple credentials without data as partial rather than current" do
    project = create(:project, :ios)
    create(
      :project_integration_setting,
      project:,
      provider: "app_store_connect",
      enabled: true,
      account_id: "issuer",
      external_project_id: "com.acme.shop",
      external_project_name: "KEY123",
      credential_reference: "APP_STORE_CONNECT_KEY"
    )

    snapshot = described_class.new(project).call

    expect(snapshot.status.state).to eq(:partial)
    expect(snapshot.fetched_at).to be_nil
    expect(snapshot.population_note).to include("opted-in usage")
  end
end
