# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::TelemetryRedactor do
  describe ".sensitive_key?" do
    it "recognizes separator and camel-case variants by semantic identity" do
      expect(%w[x-api-key api.key apiKey private-key private.key privateKey]).to all(satisfy do |key|
        described_class.sensitive_key?(key)
      end)
      expect(described_class.sensitive_key?("monkey")).to be(false)
    end
  end

  describe ".call" do
    it "redacts sensitive values nested under service and request metadata" do
      payload = {
        "service" => {
          "name" => "checkout",
          "apiKey" => "service-secret"
        },
        "request" => {
          "headers" => {
            "x-api-key" => "request-secret",
            "authorization" => "Bearer secret",
            "traceparent" => "00-safe"
          },
          "credentials" => {
            "private.key" => "private-secret"
          }
        }
      }

      result = described_class.call(payload)

      expect(result.dig("service", "name")).to eq("checkout")
      expect(result.dig("service", "apiKey")).to eq("[REDACTED]")
      expect(result.dig("request", "headers", "x-api-key")).to eq("[REDACTED]")
      expect(result.dig("request", "headers", "authorization")).to eq("[REDACTED]")
      expect(result.dig("request", "headers", "traceparent")).to eq("00-safe")
      expect(result.dig("request", "credentials", "private.key")).to eq("[REDACTED]")
    end
  end
end
