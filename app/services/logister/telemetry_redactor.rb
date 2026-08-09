# frozen_string_literal: true

module Logister
  class TelemetryRedactor
    SENSITIVE_KEY_IDENTITY_PATTERN = /(passw|email|secret|token|apikey|privatekey|authorization|cookie|setcookie|crypt|salt|certificate|otp|ssn|cvv|cvc)/
    SENSITIVE_KEY_TOKEN_PATTERN = /[^a-z0-9]key(?:\z|[^a-z0-9])/i
    SENSITIVE_IDENTITY_KEYS = %w[
      advertisingid advertisingidentifier androidid deviceid deviceserial
      hardwareid hardwareserial idfa idfv identifierforvendor imei
      installationhash installationid installationidhash meid sessionhash
      sessionid subscriberid traceid requestid spanid parentspanid userid
      useridentifier
    ].freeze
    SENSITIVE_PARENT_KEYS = {
      "installation" => %w[id idhash hash],
      "session" => %w[id idhash hash],
      "user" => %w[id idhash hash identifier]
    }.freeze
    REDACTED = "[REDACTED]"

    def self.call(value)
      new.call(value)
    end

    def self.sensitive_key?(key)
      raw_key = key.to_s
      semantic_identity = raw_key.downcase.gsub(/[^a-z0-9]/, "")

      raw_key.match?(SENSITIVE_KEY_TOKEN_PATTERN) ||
        semantic_identity.match?(SENSITIVE_KEY_IDENTITY_PATTERN) ||
        SENSITIVE_IDENTITY_KEYS.include?(semantic_identity)
    end

    def call(value)
      redact(value, [])
    end

    private

    def redact(value, path)
      case value
      when Array
        value.map { |item| redact(item, path) }
      when Hash
        value.each_with_object({}) do |(key, nested), result|
          nested_path = [ *path, key ]
          result[key] = redact_key?(key, nested, path) ? REDACTED : redact(nested, nested_path)
        end
      else
        value
      end
    end

    def redact_key?(key, value, path)
      return false unless self.class.sensitive_key?(key) || sensitive_parent_key?(path.last, key)
      return false if value == true || value == false || value.nil?

      true
    end

    def sensitive_parent_key?(parent, key)
      parent_identity = parent.to_s.downcase.gsub(/[^a-z0-9]/, "")
      key_identity = key.to_s.downcase.gsub(/[^a-z0-9]/, "")
      SENSITIVE_PARENT_KEYS.fetch(parent_identity, []).include?(key_identity)
    end
  end
end
