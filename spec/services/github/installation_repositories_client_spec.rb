# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::InstallationRepositoriesClient do
  let(:config) do
    instance_double(
      "GithubAppConfig",
      configured?: true,
      api_url: "https://api.github.test",
      api_version: "2026-03-10"
    )
  end
  let(:installation) { create(:github_installation) }
  let(:stateless_installation_token) { github_stateless_installation_token }

  it "uses long stateless installation tokens unchanged when syncing repositories" do
    token_provider = class_double(Github::InstallationToken)
    token = instance_double(Github::InstallationToken, token: stateless_installation_token)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@body, { repositories: [] }.to_json)
    response.instance_variable_set(:@read, true)
    requests = []

    expect(token_provider).to receive(:new).with(installation: installation, config: config).and_return(token)
    allow(Net::HTTP).to receive(:start) do |_host, _port, **_options, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |request|
        requests << request
        response
      end
      block.call(http)
    end

    repositories = described_class.new(token_provider: token_provider, config: config).list(installation: installation)

    expect(stateless_installation_token.length).to be >= 520
    expect(repositories).to eq([])
    expect(requests.first["Authorization"]).to eq("Bearer #{stateless_installation_token}")
    expect(requests.first["X-GitHub-Api-Version"]).to eq("2026-03-10")
  end
end
