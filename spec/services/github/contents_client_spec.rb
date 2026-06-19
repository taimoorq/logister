# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::ContentsClient do
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

  it "uses long stateless installation tokens unchanged in GitHub API requests" do
    token_provider = class_double(Github::InstallationToken)
    token = instance_double(Github::InstallationToken, token: stateless_installation_token)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@body, {
      type: "file",
      content: Base64.encode64("class Checkout; end"),
      encoding: "base64",
      sha: "abc123",
      html_url: "https://github.com/acme/api/blob/main/app/checkout.rb"
    }.to_json)
    response.instance_variable_set(:@read, true)
    requests = []

    expect(token_provider).to receive(:new).with(
      installation: installation,
      repository_ids: [ 987 ],
      permissions: { contents: "read", metadata: "read" },
      config: config
    ).and_return(token)
    allow(Net::HTTP).to receive(:start) do |_host, _port, **_options, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |request|
        requests << request
        response
      end
      block.call(http)
    end

    result = described_class.new(token_provider: token_provider, config: config).fetch(
      owner: "acme",
      repo: "api",
      path: "app/checkout.rb",
      ref: "main",
      installation: installation,
      repository_id: 987
    )

    expect(stateless_installation_token.length).to be >= 520
    expect(result.content).to eq("class Checkout; end")
    expect(requests.first["Authorization"]).to eq("Bearer #{stateless_installation_token}")
    expect(requests.first["X-GitHub-Api-Version"]).to eq("2026-03-10")
  end
end
