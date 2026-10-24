# frozen_string_literal: true

require "rails_helper"

RSpec.describe GooglePlay::CredentialResolver do
  around do |example|
    keys = %w[LOGISTER_INTEGRATION_SPEC_PLAY LOGISTER_INTEGRATION_CREDENTIAL_ENV_ALLOWLIST LEGACY_PLAY_TOKEN]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    example.run
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it "refuses to read environment variables outside the integration allowlist" do
    expect(Net::HTTP).not_to receive(:post_form)

    expect { described_class.new("SECRET_KEY_BASE").access_token }
      .to raise_error(IntegrationCredentialReference::Error) { |error| expect(error.category).to eq(:not_allowed) }
  end

  it "keeps legacy names working when the operator allowlists them" do
    ENV["LOGISTER_INTEGRATION_CREDENTIAL_ENV_ALLOWLIST"] = "LEGACY_PLAY_TOKEN"
    ENV["LEGACY_PLAY_TOKEN"] = "static-token"

    expect(described_class.new("LEGACY_PLAY_TOKEN").access_token).to eq("static-token")
  end

  it "does not expose parser text from malformed service account JSON" do
    ENV["LOGISTER_INTEGRATION_SPEC_PLAY"] = '{"client_email": "svc@example.com", "private_key": "super-secret-material'

    expect { described_class.new("LOGISTER_INTEGRATION_SPEC_PLAY").access_token }
      .to raise_error(IntegrationCredentialReference::Error) { |error|
        expect(error.message).to eq("Credential could not be parsed.")
        expect(error.message).not_to include("super-secret")
      }
  end

  it "reports an invalid private key without OpenSSL details" do
    ENV["LOGISTER_INTEGRATION_SPEC_PLAY"] = { client_email: "svc@example.com", private_key: "not-a-key", token_uri: "https://oauth2.example.test/token" }.to_json

    expect { described_class.new("LOGISTER_INTEGRATION_SPEC_PLAY").access_token }
      .to raise_error(IntegrationCredentialReference::Error, "Credential could not be parsed.")
  end
end
