# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::TelemetryPipelineMetrics do
  it "reports counts and phases without retaining SQL, bindings, or other threads' work" do
    messages = []
    allow(Rails.logger).to receive(:info) do |message|
      expect(Logister::SelfReportingGuard.suppressed?).to be(true)
      messages << message
    end
    metrics = described_class.new(operation: "acceptance", sampled: true)

    result = metrics.capture do
      metrics.count(:rows, 2)
      metrics.measure(:acceptance) do
        ActiveSupport::Notifications.instrument("sql.active_record", name: "Insert", sql: "PRIVATE SQL", binds: [ "SECRET" ]) { nil }
        Thread.new do
          ActiveSupport::Notifications.instrument("sql.active_record", name: "Other work") { nil }
        end.join
        ActiveSupport::Notifications.instrument("sql.active_record", name: "Cached", cached: true) { nil }
        :accepted
      end
    end

    expect(result).to eq(:accepted)
    expect(messages.size).to eq(1)
    expect(messages.first).not_to include("PRIVATE", "SECRET")
    summary = JSON.parse(messages.first.delete_prefix("telemetry_pipeline "))
    expect(summary.dig("counts", "rows")).to eq(2)
    expect(summary.dig("phases", "acceptance", "queries")).to eq(1)
    expect(Logister::SelfReportingGuard.suppressed?).to be(false)
  end

  it "preserves failures and unsubscribes after the operation" do
    messages = []
    allow(Rails.logger).to receive(:info) { |message| messages << message }
    metrics = described_class.new(operation: "drain", sampled: true)
    expect { metrics.capture { raise ArgumentError, "private payload" } }.to raise_error(ArgumentError, "private payload")
    expect(messages.first).to include('"error_class":"ArgumentError"')
    expect(messages.first).not_to include("private payload")
    ActiveSupport::Notifications.instrument("sql.active_record", name: "Later") { nil }
    expect(messages.size).to eq(1)
  end

  it "does not let logging failures change a successful result" do
    allow(Rails.logger).to receive(:info).and_raise(IOError)
    expect(described_class.new(operation: "drain", sampled: true).capture { :completed }).to eq(:completed)
  end

  it "leaves unsampled operations alone" do
    expect(Rails.logger).not_to receive(:info)
    metrics = described_class.new(operation: "drain", sampled: false)
    expect(metrics.capture { metrics.measure(:claim) { :result } }).to eq(:result)
  end
end
