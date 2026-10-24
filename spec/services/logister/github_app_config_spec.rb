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

  describe ".install_url" do
    before do
      allow(InstanceConfiguration).to receive(:value).and_call_original
      allow(InstanceConfiguration).to receive(:value).with("github.install_url").and_return(nil)
      allow(InstanceConfiguration).to receive(:value).with("github.app_slug").and_return("logister")
    end

    it "carries a signed setup state for the user and project" do
      user = create(:user)
      project = create(:project, user: user)

      uri = URI(described_class.install_url(user: user, project: project))
      state = URI.decode_www_form(uri.query).to_h.fetch("state")

      expect(uri.path).to eq("/apps/logister/installations/new")
      expect(state).not_to eq(project.uuid)
      expect(Github::SetupState.verify(state, user: user).project_uuid).to eq(project.uuid)
    end

    it "replaces any state embedded in a configured install URL" do
      user = create(:user)
      allow(InstanceConfiguration).to receive(:value).with("github.install_url").and_return("https://github.com/apps/logister/installations/new?state=attacker&foo=bar")

      query = URI.decode_www_form(URI(described_class.install_url(user: user)).query)

      expect(query.count { |key, _value| key == "state" }).to eq(1)
      expect(query.to_h).to include("foo" => "bar")
      expect(Github::SetupState.verify(query.to_h.fetch("state"), user: user)).to be_present
    end

    it "omits the state when no user starts the install" do
      expect(described_class.install_url).to eq("https://github.com/apps/logister/installations/new")
    end
  end
end
