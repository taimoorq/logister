# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::DeploymentRecorder do
  Configuration = Struct.new(:enabled, :api_key, :endpoint, :timeout_seconds, keyword_init: true)

  before do
    allow(Logister).to receive(:respond_to?).and_call_original
    allow(Logister).to receive(:respond_to?).with(:record_deployment).and_return(false)
  end

  it "returns false when Logister is not configured with an API key" do
    configuration = Configuration.new(
      enabled: true,
      api_key: nil,
      endpoint: "https://logister.example.com/api/v1/ingest_events",
      timeout_seconds: 2
    )

    expect(described_class.call({}, configuration: configuration)).to be(false)
  end

  it "posts deployment payloads to the derived deployment endpoint" do
    configuration = Configuration.new(
      enabled: true,
      api_key: "token",
      endpoint: "https://logister.example.com/api/v1/ingest_events",
      timeout_seconds: 2
    )
    http = instance_double(Net::HTTP)
    response = Net::HTTPCreated.new("1.1", "201", "Created")
    captured_request = nil
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request) do |request|
      captured_request = request
      response
    end

    result = described_class.call(
      {
        release: "v2.6.1",
        repository: "taimoorq/logister",
        commit_sha: "abc1234"
      },
      configuration: configuration
    )

    expect(result).to be(true)
    expect(Net::HTTP).to have_received(:start).with(
      "logister.example.com",
      443,
      use_ssl: true,
      open_timeout: 2,
      read_timeout: 2
    )
    expect(captured_request.path).to eq("/api/v1/deployments")
    expect(captured_request["Authorization"]).to eq("Bearer token")
    expect(JSON.parse(captured_request.body)).to eq(
      "deployment" => {
        "release" => "v2.6.1",
        "repository" => "taimoorq/logister",
        "commit_sha" => "abc1234"
      }
    )
  end
end
