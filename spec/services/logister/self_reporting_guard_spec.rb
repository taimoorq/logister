# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::SelfReportingGuard do
  it "suppresses reporting throughout telemetry write requests" do
    observed = nil
    app = lambda do |_env|
      observed = described_class.suppressed?
      [ 201, {}, [] ]
    end

    described_class.new(app).call("PATH_INFO" => "/api/v1/ingest_events")

    expect(observed).to be(true)
    expect(described_class.suppressed?).to be(false)
  end

  it "does not suppress reporting for product requests" do
    observed = nil
    app = lambda do |_env|
      observed = described_class.suppressed?
      [ 200, {}, [] ]
    end

    described_class.new(app).call("PATH_INFO" => "/dashboard")

    expect(observed).to be(false)
  end

  it "suppresses reporting within an explicit block and restores the state" do
    observed = described_class.suppress { described_class.suppressed? }

    expect(observed).to be(true)
    expect(described_class.suppressed?).to be(false)
  end

  it "restores an existing suppressed state after an explicit block raises" do
    ActiveSupport::IsolatedExecutionState[described_class::STATE_KEY] = true

    expect do
      described_class.suppress { raise "boom" }
    end.to raise_error("boom")

    expect(described_class.suppressed?).to be(true)
  ensure
    ActiveSupport::IsolatedExecutionState[described_class::STATE_KEY] = nil
  end

  it "restores the previous state when the application raises" do
    ActiveSupport::IsolatedExecutionState[described_class::STATE_KEY] = true
    app = ->(_env) { raise "boom" }

    expect do
      described_class.new(app).call("PATH_INFO" => "/api/v1/check_ins")
    end.to raise_error("boom")

    expect(described_class.suppressed?).to be(true)
  ensure
    ActiveSupport::IsolatedExecutionState[described_class::STATE_KEY] = nil
  end

  it "recognizes only telemetry write paths and their descendants" do
    expect(described_class.reporting_path?("/api/v1/deployments/123")).to be(true)
    expect(described_class.reporting_path?("/api/v1/ingest_events_extra")).to be(false)
    expect(described_class.reporting_path?("/api/v1/cli/projects")).to be(false)
  end

  it "causes the configured before-notify hook to drop recursive telemetry" do
    hook = Logister.configuration.before_notify
    result = nil
    app = lambda do |_env|
      result = hook.call(event_type: "metric", message: "db.query", context: {})
      [ 201, {}, [] ]
    end

    described_class.new(app).call("PATH_INFO" => "/api/v1/ingest_events")

    expect(result).to be(false)
  end
end
