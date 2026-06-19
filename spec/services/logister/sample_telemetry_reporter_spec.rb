# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::SampleTelemetryReporter do
  let(:source_context) do
    instance_double(
      Logister::SourceContext,
      repository: "taimoorq/logister",
      commit_sha: "abc1234",
      branch: "main",
      release: "v2.6.1",
      environment: "test",
      service: "logister",
      deployment_payload: {
        release: "v2.6.1",
        environment: "test",
        repository: "taimoorq/logister",
        commit_sha: "abc1234",
        branch: "main"
      }
    )
  end

  before do
    allow(Logister).to receive(:add_breadcrumb)
    allow(Logister).to receive(:add_dependency)
    allow(Logister::DeploymentRecorder).to receive(:call).and_return(true)
    allow(Logister).to receive(:report_log).and_return(true)
    allow(Logister).to receive(:report_metric).and_return(true)
    allow(Logister).to receive(:report_transaction).and_return(true)
    allow(Logister).to receive(:report_span).and_return(true)
    allow(Logister).to receive(:report_check_in).and_return(true)
    allow(Logister).to receive(:report_error).and_return(true)
    allow(Logister).to receive(:flush).and_return(true)
  end

  it "emits every telemetry family plus a deployment record" do
    result = described_class.call(source_context: source_context)

    expect(result).to include(
      deployment: true,
      log: true,
      metric: true,
      transaction: true,
      check_in: true,
      error: true,
      flushed: true
    )
    expect(result[:spans]).to eq([ true, true, true, true ])
    expect(Logister::DeploymentRecorder).to have_received(:call).with(
      release: "v2.6.1",
      environment: "test",
      repository: "taimoorq/logister",
      commit_sha: "abc1234",
      branch: "main"
    )
    expect(Logister).to have_received(:report_log).with(hash_including(message: "Logister sample telemetry log"))
    expect(Logister).to have_received(:report_metric).with(hash_including(message: "logister.self_test.sample_value", value: 1, unit: "count"))
    expect(Logister).to have_received(:report_transaction).with(hash_including(name: "logister.self_test.transaction"))
    expect(Logister).to have_received(:report_span).exactly(4).times
    expect(Logister).to have_received(:report_check_in).with(hash_including(slug: "logister.self_test"))
    expect(Logister).to have_received(:report_error).with(
      an_instance_of(Logister::SampleTelemetryReporter::SampleError),
      hash_including(context: hash_including(repository: "taimoorq/logister"))
    )
  end

  it "uses repo-relative backtrace paths for source lookup testing" do
    described_class.call(source_context: source_context)

    expect(Logister).to have_received(:report_error) do |error, **_kwargs|
      expect(error.backtrace.first).to start_with("app/services/logister/sample_telemetry_reporter.rb:")
    end
  end
end
