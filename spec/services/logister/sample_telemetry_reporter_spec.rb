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

  it "emits only a sample error, preserving source context" do
    result = described_class.call(source_context: source_context)

    expect(result).to eq(error: true, flushed: true)
    expect(Logister::DeploymentRecorder).not_to have_received(:call)
    %i[report_log report_metric report_transaction report_span report_check_in].each do |method|
      expect(Logister).not_to have_received(method)
    end
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
