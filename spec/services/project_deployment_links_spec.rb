# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectDeploymentLinks do
  def deployment_with(metadata)
    build(:project_deployment, repository_full_name: "acme/storefront", release: "2026.06.18", metadata: metadata)
  end

  it "returns stored GitHub URLs" do
    links = described_class.new(deployment_with(
      "pull_request_number" => "42",
      "pull_request_url" => "https://github.com/acme/storefront/pull/42",
      "release_url" => "https://github.com/acme/storefront/releases/tag/v1"
    ))

    expect(links.pull_request_url).to eq("https://github.com/acme/storefront/pull/42")
    expect(links.release_url).to eq("https://github.com/acme/storefront/releases/tag/v1")
    expect(links.pull_request_label).to eq("PR #42")
  end

  it "ignores stored metadata URLs that predate host validation" do
    links = described_class.new(deployment_with(
      "pull_request_number" => "42",
      "pull_request_url" => "javascript:alert(document.cookie)",
      "release_url" => "https://phish.example/login"
    ))

    expect(links.pull_request_url).to eq("https://github.com/acme/storefront/pull/42")
    expect(links.release_url).to eq("https://github.com/acme/storefront/releases/tag/2026.06.18")
  end

  it "ignores stored pull request numbers that are not plain digits" do
    links = described_class.new(deployment_with("pull_request_number" => "../../evil/repo"))

    expect(links.pull_request_number).to be_nil
    expect(links.pull_request_label).to be_nil
    expect(links.pull_request_url).to be_nil
  end
end
