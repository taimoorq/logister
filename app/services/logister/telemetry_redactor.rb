# frozen_string_literal: true

module Logister
  class TelemetryRedactor
    SENSITIVE_KEY_IDENTITY_PATTERN = /(passw|email|secret|token|apikey|privatekey|authorization|cookie|setcookie|crypt|salt|certificate|otp|ssn|cvv|cvc)/
    SENSITIVE_KEY_TOKEN_PATTERN = /[^a-z0-9]key(?:\z|[^a-z0-9])/i
    REDACTED = "[REDACTED]"

    def self.call(value)
      new.call(value)
    end

    def self.sensitive_key?(key)
      raw_key = key.to_s
      semantic_identity = raw_key.downcase.gsub(/[^a-z0-9]/, "")

      raw_key.match?(SENSITIVE_KEY_TOKEN_PATTERN) || semantic_identity.match?(SENSITIVE_KEY_IDENTITY_PATTERN)
    end

    def call(value)
      redact(value)
    end

    private

    def redact(value)
      case value
      when Array
        value.map { |item| redact(item) }
      when Hash
        value.each_with_object({}) do |(key, nested), result|
          result[key] = redact_key?(key, nested) ? REDACTED : redact(nested)
        end
      else
        value
      end
    end

    def redact_key?(key, value)
      return false unless self.class.sensitive_key?(key)
      return false if value == true || value == false || value.nil?

      true
    end
  end
end
