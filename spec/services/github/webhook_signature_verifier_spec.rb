# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::WebhookSignatureVerifier do
  it "accepts a valid sha256 signature" do
    payload = '{"zen":"Keep it logically awesome."}'
    signature = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", "secret", payload)}"
    verifier = described_class.new(secret: "secret")

    expect(verifier.valid?(payload: payload, signature: signature)).to be(true)
  end

  it "rejects invalid signatures" do
    verifier = described_class.new(secret: "secret")

    expect(verifier.valid?(payload: "{}", signature: "sha256=bad")).to be(false)
  end

  it "is not configured without a secret" do
    verifier = described_class.new(secret: nil)

    expect(verifier).not_to be_configured
  end
end
