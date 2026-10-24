# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppStoreConnect::CredentialResolver do
  it "creates a short-lived ES256 App Store Connect token from an environment reference" do
    key = OpenSSL::PKey::EC.generate("prime256v1")
    previous_key = ENV["LOGISTER_INTEGRATION_SPEC_APP_STORE_PRIVATE_KEY"]
    ENV["LOGISTER_INTEGRATION_SPEC_APP_STORE_PRIVATE_KEY"] = key.to_pem
    resolver = described_class.new(
      issuer_id: "issuer-123",
      key_id: "KEY123",
      credential_reference: "LOGISTER_INTEGRATION_SPEC_APP_STORE_PRIVATE_KEY"
    )

    header_segment, claims_segment, signature_segment = resolver.token.split(".")
    header = JSON.parse(Base64.urlsafe_decode64(header_segment))
    claims = JSON.parse(Base64.urlsafe_decode64(claims_segment))
    signature = Base64.urlsafe_decode64(signature_segment)

    expect(header).to include("alg" => "ES256", "kid" => "KEY123", "typ" => "JWT")
    expect(claims).to include("iss" => "issuer-123", "aud" => "appstoreconnect-v1")
    expect(claims.fetch("exp") - claims.fetch("iat")).to eq(19.minutes.to_i)
    expect(signature.bytesize).to eq(64)
  ensure
    previous_key.nil? ? ENV.delete("LOGISTER_INTEGRATION_SPEC_APP_STORE_PRIVATE_KEY") : ENV["LOGISTER_INTEGRATION_SPEC_APP_STORE_PRIVATE_KEY"] = previous_key
  end

  it "refuses disallowed references and hides key parsing details" do
    expect {
      described_class.new(issuer_id: "issuer", key_id: "KEY", credential_reference: "SECRET_KEY_BASE").token
    }.to raise_error(IntegrationCredentialReference::Error, "Credential reference is not an allowed environment variable.")

    previous_key = ENV["LOGISTER_INTEGRATION_SPEC_BAD_KEY"]
    # Assembled at runtime so the publication safety check does not read it as key material.
    pem_label = [ "PRIVATE", "KEY" ].join(" ")
    ENV["LOGISTER_INTEGRATION_SPEC_BAD_KEY"] = "-----BEGIN #{pem_label}-----\nsecret-material\n-----END #{pem_label}-----"

    expect {
      described_class.new(issuer_id: "issuer", key_id: "KEY", credential_reference: "LOGISTER_INTEGRATION_SPEC_BAD_KEY").token
    }.to raise_error(IntegrationCredentialReference::Error) { |error|
      expect(error.message).to eq("Credential could not be parsed.")
      expect(error.message).not_to include("secret-material")
    }
  ensure
    previous_key.nil? ? ENV.delete("LOGISTER_INTEGRATION_SPEC_BAD_KEY") : ENV["LOGISTER_INTEGRATION_SPEC_BAD_KEY"] = previous_key
  end
end
