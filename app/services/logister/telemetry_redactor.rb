# frozen_string_literal: true

module Logister
  class TelemetryRedactor
    SENSITIVE_KEY_PATTERN = /(passw|email|secret|token|_key|apikey|api_key|authorization|cookie|set-cookie|crypt|salt|certificate|otp|ssn|cvv|cvc)/i
    REDACTED = "[REDACTED]"

    def self.call(value)
      new.call(value)
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
      return false unless key.to_s.match?(SENSITIVE_KEY_PATTERN)
      return false if value == true || value == false || value.nil?

      true
    end
  end
end
