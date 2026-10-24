# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::RequestOriginConfiguration do
  describe ".allowed_hosts" do
    it "does not enforce host authorization until the operator names a host" do
      expect(described_class.allowed_hosts({})).to eq([])
    end

    it "allows the public URL host and any extra hosts" do
      env = {
        "LOGISTER_PUBLIC_URL" => "https://Errors.Example.com:8443",
        "LOGISTER_ALLOWED_HOSTS" => " internal.example.com, ,errors.example.com "
      }

      expect(described_class.allowed_hosts(env)).to eq([ "errors.example.com", "internal.example.com" ])
    end

    it "rejects a malformed public URL" do
      expect { described_class.allowed_hosts("LOGISTER_PUBLIC_URL" => "https://bad host") }.to raise_error(ArgumentError, /LOGISTER_PUBLIC_URL/)
    end
  end

  describe ".trusted_proxies" do
    it "keeps the Rails default when unset" do
      expect(described_class.trusted_proxies({})).to be_nil
    end

    it "adds proxies to the loopback and private defaults" do
      proxies = described_class.trusted_proxies("LOGISTER_TRUSTED_PROXIES" => "173.245.48.0/20, 2400:cb00::/32")

      expect(proxies).to include(*ActionDispatch::RemoteIp::TRUSTED_PROXIES)
      expect(proxies.any? { |proxy| proxy.include?(IPAddr.new("173.245.48.10")) }).to be(true)
      expect(proxies.any? { |proxy| proxy.include?(IPAddr.new("2400:cb00::1")) }).to be(true)
    end

    it "rejects an invalid address" do
      expect { described_class.trusted_proxies("LOGISTER_TRUSTED_PROXIES" => "not-an-ip") }.to raise_error(ArgumentError, /not-an-ip/)
    end
  end
end
