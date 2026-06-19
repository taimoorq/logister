# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::InstallationToken do
  let(:config) do
    instance_double(
      "GithubAppConfig",
      configured?: true,
      api_url: "https://api.github.test",
      api_version: "2026-03-10",
      stateless_s2s_token_override: stateless_s2s_token_override
    )
  end
  let(:jwt_provider) { instance_double(Github::AppJwt, token: "app-jwt") }
  let(:installation) { create(:github_installation, installation_id: 42) }
  let(:stateless_s2s_token_override) { nil }
  let(:stateless_installation_token) { github_stateless_installation_token }

  around do |example|
    Rails.cache.clear
    example.run
  ensure
    Rails.cache.clear
  end

  it "accepts the longer stateless ghs installation token as an opaque string" do
    response = installation_token_response(stateless_installation_token)
    requests = capture_http_requests(response)

    token = described_class.new(
      installation: installation,
      repository_ids: 123,
      permissions: { contents: "read", metadata: "read" },
      config: config,
      jwt_provider: jwt_provider
    ).token

    expect(stateless_installation_token.length).to be >= 520
    expect(token).to eq(stateless_installation_token)
    expect(requests.first["Authorization"]).to eq("Bearer app-jwt")
    expect(requests.first["X-GitHub-Api-Version"]).to eq("2026-03-10")
    expect(requests.first[described_class::STATELESS_S2S_TOKEN_HEADER]).to be_nil
    expect(JSON.parse(requests.first.body)).to eq(
      "repository_ids" => [ 123 ],
      "permissions" => { "contents" => "read", "metadata" => "read" }
    )
  end

  it "can force GitHub's stateless token format for proactive rollout testing" do
    allow(config).to receive(:stateless_s2s_token_override).and_return("enabled")
    response = installation_token_response(stateless_installation_token)
    requests = capture_http_requests(response)

    described_class.new(
      installation: installation,
      config: config,
      jwt_provider: jwt_provider
    ).token

    expect(requests.first[described_class::STATELESS_S2S_TOKEN_HEADER]).to eq("enabled")
  end

  it "can request classic opaque tokens while operators diagnose rollout issues" do
    allow(config).to receive(:stateless_s2s_token_override).and_return("disabled")
    response = installation_token_response("ghs_classicopaqueinstallationtokenvalue123456")
    requests = capture_http_requests(response)

    described_class.new(
      installation: installation,
      config: config,
      jwt_provider: jwt_provider
    ).token

    expect(requests.first[described_class::STATELESS_S2S_TOKEN_HEADER]).to eq("disabled")
  end

  def installation_token_response(token)
    response = Net::HTTPCreated.new("1.1", "201", "Created")
    response.instance_variable_set(:@body, { token: token, expires_at: 1.hour.from_now.iso8601 }.to_json)
    response.instance_variable_set(:@read, true)
    response
  end

  def capture_http_requests(response)
    requests = []

    allow(Net::HTTP).to receive(:start) do |_host, _port, **_options, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |request|
        requests << request
        response
      end
      block.call(http)
    end

    requests
  end
end
