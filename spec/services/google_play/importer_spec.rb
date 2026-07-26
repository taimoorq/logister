# frozen_string_literal: true

require "rails_helper"

RSpec.describe GooglePlay::Importer do
  let(:project) { create(:project, :android) }
  let(:setting) do
    create(
      :project_integration_setting,
      project: project,
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.shop",
      credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS"
    )
  end
  let(:client) do
    instance_double(
      GooglePlay::DeveloperReportingClient,
      release_filter_options: {
        "tracks" => [
          {
            "displayName" => "Production",
            "type" => "PRODUCTION",
            "servingReleases" => [ { "displayName" => "1.4.0", "versionCodes" => [ "42" ] } ]
          }
        ]
      },
      crash_rates: {
        "rows" => [
          {
            "dimensions" => [ { "dimension" => "versionCode", "int64Value" => "42" } ],
            "metrics" => [ { "metric" => "userPerceivedCrashRate", "decimalValue" => { "value" => "0.01" } } ]
          }
        ]
      },
      anr_rates: { "rows" => [] },
      anomalies: { "anomalies" => [] }
    )
  end

  it "stores a provenance-labeled snapshot without merging it into SDK metrics" do
    reporting = described_class.new(setting, client: client).call

    expect(reporting).to include("source" => "google_play_developer_reporting")
    expect(reporting.dig("window", "time_zone")).to eq("America/Los_Angeles")
    expect(setting.reload.last_imported_at).to be_present
    expect(setting.metadata.dig("reporting", "crash_rates", "rows")).to be_present
  end

  it "maps selected tracks to active version codes before filtering metric rows" do
    setting.update!(metadata: { "track_allowlist" => [ "production" ] })
    allow(client).to receive(:crash_rates).and_return(
      "rows" => [
        { "dimensions" => [ { "dimension" => "versionCode", "int64Value" => "42" } ] },
        { "dimensions" => [ { "dimension" => "versionCode", "int64Value" => "41" } ] }
      ]
    )

    reporting = described_class.new(setting, client: client).call

    expect(reporting["selected_tracks"]).to eq([ "production" ])
    expect(reporting.dig("crash_rates", "rows").pluck("dimensions")).to eq([
      [ { "dimension" => "versionCode", "int64Value" => "42" } ]
    ])
  end

  it "records importer failures for operator diagnosis" do
    allow(client).to receive(:release_filter_options).and_raise(GooglePlay::DeveloperReportingClient::Error, "permission denied")

    expect { described_class.new(setting, client: client).call }.to raise_error(GooglePlay::DeveloperReportingClient::Error)
    expect(setting.reload.metadata.dig("last_error", "message")).to eq("permission denied")
  end
end
