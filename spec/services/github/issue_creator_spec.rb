# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::IssueCreator do
  let(:config) do
    instance_double(
      "GithubAppConfig",
      configured?: true,
      api_url: "https://api.github.test",
      api_version: "2022-11-28"
    )
  end
  let(:stateless_installation_token) { github_stateless_installation_token }

  it "creates an issue with an installation token scoped to issues:write" do
    project = create(:project, name: "Checkout API")
    installation = create(:github_installation, permissions: { "contents" => "read", "metadata" => "read", "issues" => "write" })
    repository = create(:project_source_repository, project: project, github_installation: installation, full_name: "acme/checkout")
    group = create(:error_group, project: project, title: "RuntimeError in Checkout", fingerprint: "checkout-runtime")
    token_provider = class_double(Github::InstallationToken)
    token = instance_double(Github::InstallationToken, token: stateless_installation_token)
    response = Net::HTTPCreated.new("1.1", "201", "Created")
    response.instance_variable_set(:@body, {
      html_url: "https://github.com/acme/checkout/issues/42",
      number: 42,
      title: "[Checkout API] RuntimeError in Checkout"
    }.to_json)
    response.instance_variable_set(:@read, true)
    requests = []

    expect(token_provider).to receive(:new).with(
      installation: installation,
      repository_ids: repository.external_id,
      permissions: { issues: "write", metadata: "read" },
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

    result = described_class.call(
      project: project,
      group: group,
      event: nil,
      source_excerpt: nil,
      repository: repository,
      logister_url: "https://logister.example/inbox",
      token_provider: token_provider,
      config: config
    )

    expect(result.html_url).to eq("https://github.com/acme/checkout/issues/42")
    expect(result.number).to eq(42)
    expect(stateless_installation_token.length).to be >= 520
    expect(requests.first["Authorization"]).to eq("Bearer #{stateless_installation_token}")
    expect(requests.first["X-GitHub-Api-Version"]).to eq("2022-11-28")
    expect(JSON.parse(requests.first.body)).to include(
      "title" => "[Checkout API] RuntimeError in Checkout",
      "body" => a_string_including("Fingerprint: `checkout-runtime`")
    )
  end

  it "requires an installation with Issues write permission" do
    project = create(:project)
    repository = create(:project_source_repository, project: project, full_name: "acme/checkout")
    group = create(:error_group, project: project)

    expect do
      described_class.call(
        project: project,
        group: group,
        event: nil,
        source_excerpt: nil,
        repository: repository,
        logister_url: nil,
        config: config
      )
    end.to raise_error(Github::IssueCreator::PermissionError, /Issues write/)
  end
end
