# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::DeploymentRecorder do
  it "does not submit standalone deployments through either SDK or HTTP" do
    expect(Logister).not_to receive(:record_deployment)
    expect(Logister::HttpClient).not_to receive(:request)
    expect(described_class.call({ release: "test" })).to be(false)
  end
end
