# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectMobileOverview do
  it "uses receipt time for operational freshness and exposes identity coverage" do
    now = Time.zone.parse("2026-08-09T18:00:00Z")
    project = create(:project, :ios)
    group = create(:error_group, project: project)
    occurrence = create(
      :error_occurrence,
      error_group: group,
      occurred_at: 10.days.ago,
      installation_hash: "install-1",
      session_hash: nil
    )
    occurrence.update_columns(
      created_at: now - 15.minutes,
      dimensions: {
        "app_version" => "4.2.0",
        "build_number" => "310",
        "distribution_channel" => "testflight",
        "time_precision" => "reporting_interval",
        "diagnostic_source" => "metrickit"
      }
    )

    overview = described_class.new(project, now: now).call

    expect(overview.newly_received_issues).to eq(1)
    expect(overview.latest_diagnostic_received_at).to be_within(1.second).of(now - 15.minutes)
    expect(overview.current_release.label).to eq("4.2.0 (310)")
    expect(overview.installation_coverage.state).to eq(:complete)
    expect(overview.session_coverage.state).to eq(:not_collected)
    expect(overview.source_counts).to eq("metrickit" => 1)
  end

  it "renders an honest empty state without denominator claims" do
    overview = described_class.new(create(:project, :android)).call

    expect(overview.open_issues).to eq(0)
    expect(overview.current_release).to be_nil
    expect(overview.installation_coverage.state).to eq(:not_collected)
    expect(overview.installation_coverage.total).to eq(0)
  end
end
