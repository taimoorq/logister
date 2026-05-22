# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ReleaseUpdateChecker do
  around do |example|
    original_enabled = ENV["LOGISTER_UPDATE_CHECKS_ENABLED"]
    original_release = ENV["LOGISTER_RELEASE"]
    Rails.cache.clear
    example.run
  ensure
    ENV["LOGISTER_UPDATE_CHECKS_ENABLED"] = original_enabled
    ENV["LOGISTER_RELEASE"] = original_release
    Rails.cache.clear
  end

  it "returns an update when GitHub has a newer release" do
    ENV["LOGISTER_UPDATE_CHECKS_ENABLED"] = "true"
    ENV["LOGISTER_RELEASE"] = "v2.0.3"
    checker = described_class.new

    allow(checker).to receive(:fetch_latest_release).and_return(
      "tag_name" => "v2.0.4",
      "name" => "Logister v2.0.4",
      "html_url" => "https://github.com/taimoorq/logister/releases/tag/v2.0.4",
      "published_at" => "2026-05-22T22:00:00Z"
    )

    result = checker.call

    expect(result).to have_attributes(
      current_version: "2.0.3",
      latest_version: "2.0.4",
      release_name: "Logister v2.0.4",
      release_url: "https://github.com/taimoorq/logister/releases/tag/v2.0.4"
    )
    expect(result.notification_key).to eq("release_update:2.0.4")
  end

  it "does not return an update when the current release is latest" do
    ENV["LOGISTER_UPDATE_CHECKS_ENABLED"] = "true"
    ENV["LOGISTER_RELEASE"] = "v2.0.3"
    checker = described_class.new

    allow(checker).to receive(:fetch_latest_release).and_return("tag_name" => "v2.0.3")

    expect(checker.call).to be_nil
  end

  it "is disabled by default in tests" do
    ENV.delete("LOGISTER_UPDATE_CHECKS_ENABLED")
    checker = described_class.new

    expect(checker).not_to receive(:fetch_latest_release)
    expect(checker.call).to be_nil
  end
end
