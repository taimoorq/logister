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

  { "1h" => 1.hour, "6h" => 6.hours, "24h" => 24.hours, "7d" => 7.days }.each do |window, duration|
    it "preserves #{window} as an absolute Connected time range" do
      freeze_time do
        scope = described_class.from(project: create(:project), source: { window:, environment: "staging", release: "1.2" })
        projection = scope.project_for(:connections)

        expect(projection.params).to eq(environment: "staging", release: "1.2",
                                       from: (Time.current - duration).iso8601(6), to: Time.current.iso8601(6))
        expect(projection.dropped).to be_empty
      end
    end
  end

  it "reports unsupported Connected filters while retaining supported dimensions" do
    scope = described_class.from(project: create(:project, :ios), source: {
      window: "30d", environment: "production", release: "1.2", build_number: "42",
      distribution: "testflight", source: "metrickit", platform: "ios"
    })
    projection = scope.project_for(:connections)

    expect(projection.params).to eq(environment: "production", release: "1.2", build_number: "42")
    expect(projection.dropped).to contain_exactly(:window, :distribution, :source, :platform)
  end
end
