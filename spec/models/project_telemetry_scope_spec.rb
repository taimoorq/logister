# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectTelemetryScope do
  it "projects one mobile scope into page-specific allow-listed parameters" do
    project = create(:project, :ios)
    scope = described_class.from(
      project:,
      source: {
        window: "7d",
        environment: "production",
        release: "com.acme.shop@4.2.0+310",
        build_number: "310",
        distribution: "TestFlight",
        source: "MetricKit",
        platform: "iOS"
      }
    )

    expect(scope).to be_frozen
    expect(scope.project_for(:activity).params).to include(
      period: "7d",
      build_number: "310",
      channel: "testflight",
      source: "metrickit",
      platform: "ios"
    )
    expect(scope.project_for(:insights).params.fetch(:attributes)).to eq(
      build_number: "310",
      distribution_channel: "testflight",
      evidence_source: "metrickit",
      platform: "ios"
    )
    expect(scope.project_for(:inbox).params).to include(
      time_range: "7d",
      diagnostic_source: "metrickit",
      distribution_channel: "testflight",
      apple_platform: "ios"
    )
  end

  it "reports a time window that the destination cannot preserve" do
    scope = described_class.from(project: create(:project, :android), source: { window: "1h", source: "sdk" })

    activity = scope.project_for(:activity)

    expect(activity.params).to eq(source: "sdk")
    expect(activity.dropped).to include(:window)
  end

  it "does not carry mobile-only dimensions into a service project" do
    scope = described_class.from(
      project: create(:project),
      source: { window: "24h", build_number: "42", distribution: "production", source: "sdk", platform: "android" }
    )

    expect(scope.to_h).to eq(window: "24h")
    expect(scope.project_for(:insights).params).to eq(window: "24h")
  end
end
