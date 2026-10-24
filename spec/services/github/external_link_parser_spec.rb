# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::ExternalLinkParser do
  it "parses GitHub issue URLs into canonical metadata" do
    result = described_class.call("https://github.com/acme/storefront/issues/42?notification_referrer_id=1")

    expect(result).to have_attributes(
      url: "https://github.com/acme/storefront/issues/42",
      link_type: "issue",
      repository_full_name: "acme/storefront",
      external_id: "42",
      title: "acme/storefront issue #42"
    )
  end

  it "parses GitHub pull request URLs" do
    result = described_class.call("https://github.com/acme/storefront/pull/17")

    expect(result).to have_attributes(
      url: "https://github.com/acme/storefront/pull/17",
      link_type: "pull_request",
      title: "acme/storefront PR #17"
    )
  end

  it "supports a configured GitHub Enterprise web host" do
    result = described_class.call(
      "https://github.internal/acme/storefront/issues/8",
      web_url: "https://github.internal"
    )

    expect(result.repository_full_name).to eq("acme/storefront")
  end

  it "rejects unrelated URLs" do
    expect(described_class.call("https://example.com/acme/storefront/issues/42")).to be_nil
    expect(described_class.call("https://github.com/acme/storefront/actions/runs/42")).to be_nil
  end

  describe ".allowed_web_url" do
    it "accepts https URLs on github.com or the configured web host" do
      url = "https://github.com/acme/storefront/blob/main/app/models/order.rb#L12"

      expect(described_class.allowed_web_url(url)).to eq(url)
      expect(described_class.allowed_web_url("https://github.internal/acme/storefront", web_url: "https://github.internal")).to eq("https://github.internal/acme/storefront")
    end

    it "rejects other schemes, hosts, credentials, and malformed URLs" do
      [
        "http://github.com/acme/storefront",
        "javascript:alert(1)",
        "https://github.com.evil.example/acme/storefront",
        "https://github.com@evil.example/acme/storefront",
        "https://user:pass@github.com/acme/storefront",
        "https://github.com/acme/storefront) [click](https://evil.example",
        "",
        nil
      ].each do |url|
        expect(described_class.allowed_web_url(url)).to be_nil, "expected #{url.inspect} to be rejected"
      end
    end
  end
end
