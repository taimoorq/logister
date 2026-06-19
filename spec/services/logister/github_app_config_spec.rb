# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::GithubAppConfig do
  around do |example|
    original_value = ENV["LOGISTER_GITHUB_STATELESS_S2S_TOKEN"]
    example.run
  ensure
    ENV["LOGISTER_GITHUB_STATELESS_S2S_TOKEN"] = original_value
  end

  it "accepts GitHub stateless S2S token rollout override values" do
    ENV["LOGISTER_GITHUB_STATELESS_S2S_TOKEN"] = " enabled "
    expect(described_class.stateless_s2s_token_override).to eq("enabled")

    ENV["LOGISTER_GITHUB_STATELESS_S2S_TOKEN"] = "DISABLED"
    expect(described_class.stateless_s2s_token_override).to eq("disabled")
  end

  it "ignores blank or unknown stateless S2S token rollout override values" do
    ENV["LOGISTER_GITHUB_STATELESS_S2S_TOKEN"] = ""
    expect(described_class.stateless_s2s_token_override).to be_nil

    ENV["LOGISTER_GITHUB_STATELESS_S2S_TOKEN"] = "maybe"
    expect(described_class.stateless_s2s_token_override).to be_nil
  end
end
