# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::ConfigurationDiagnostics do
  class FakeGithubConfig
    class << self
      attr_accessor :app_id, :private_key_pem, :webhook_secret
    end
  end

  around do |example|
    FakeGithubConfig.app_id = nil
    FakeGithubConfig.private_key_pem = nil
    FakeGithubConfig.webhook_secret = nil
    example.run
  end

  it "reports ready when all required self-host settings are present" do
    FakeGithubConfig.app_id = "123"
    FakeGithubConfig.private_key_pem = "private"
    FakeGithubConfig.webhook_secret = "secret"

    result = described_class.call(
      config: FakeGithubConfig,
      setup_url: "https://logister.example/github/setup",
      webhook_url: "https://logister.example/github/webhooks",
      install_url: "https://github.com/apps/logister/installations/new"
    )

    expect(result).to be_ready
    expect(result.missing_checks).to be_empty
    expect(result.setup_url).to eq("https://logister.example/github/setup")
    expect(result.webhook_url).to eq("https://logister.example/github/webhooks")
  end

  it "reports missing checks without exposing secret values" do
    result = described_class.call(
      config: FakeGithubConfig,
      setup_url: "https://logister.example/github/setup",
      webhook_url: "https://logister.example/github/webhooks",
      install_url: nil
    )

    expect(result).not_to be_ready
    expect(result.missing_checks.map(&:key)).to eq([ :app_id, :private_key, :webhook_secret, :install_url ])
    expect(result.checks.map(&:message).join(" ")).to include("LOGISTER_GITHUB_APP_PRIVATE_KEY is missing")
    expect(result.checks.map(&:message).join(" ")).not_to include("secret")
  end
end
