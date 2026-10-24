# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCredentialReference do
  around do |example|
    keys = %w[LOGISTER_INTEGRATION_CREDENTIAL_ENV_ALLOWLIST LOGISTER_INTEGRATION_SPEC_CREDENTIAL LEGACY_PLAY_CREDENTIALS]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "allows prefixed names and operator-allowlisted names only" do
    ENV["LOGISTER_INTEGRATION_CREDENTIAL_ENV_ALLOWLIST"] = " LEGACY_PLAY_CREDENTIALS , OTHER_NAME"

    expect(described_class.allowed?("LOGISTER_INTEGRATION_GOOGLE_PLAY")).to be(true)
    expect(described_class.allowed?("LEGACY_PLAY_CREDENTIALS")).to be(true)
    expect(described_class.allowed?("SECRET_KEY_BASE")).to be(false)
    expect(described_class.allowed?("AWS_SECRET_ACCESS_KEY")).to be(false)
    expect(described_class.allowed?("LOGISTER_INTEGRATION_CREDENTIAL_ENV_ALLOWLIST")).to be(false)
    expect(described_class.allowed?("logister_integration_lowercase")).to be(false)
    expect(described_class.allowed?("")).to be(false)
  end

  it "raises generic categories without reading a disallowed variable" do
    expect(ENV).not_to receive(:[]).with("SECRET_KEY_BASE")

    expect { described_class.fetch!("SECRET_KEY_BASE") }.to raise_error(described_class::Error) { |error|
      expect(error.category).to eq(:not_allowed)
      expect(error.message).to eq("Credential reference is not an allowed environment variable.")
    }
  end

  it "reports a missing or blank variable as not configured" do
    expect { described_class.fetch!("LOGISTER_INTEGRATION_SPEC_CREDENTIAL") }.to raise_error(described_class::Error, "Credential is not configured.")

    ENV["LOGISTER_INTEGRATION_SPEC_CREDENTIAL"] = "  "
    expect { described_class.fetch!("LOGISTER_INTEGRATION_SPEC_CREDENTIAL") }.to raise_error(described_class::Error, "Credential is not configured.")

    ENV["LOGISTER_INTEGRATION_SPEC_CREDENTIAL"] = " value "
    expect(described_class.fetch!("LOGISTER_INTEGRATION_SPEC_CREDENTIAL")).to eq("value")
  end
end
