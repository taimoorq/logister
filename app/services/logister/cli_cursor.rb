# frozen_string_literal: true

require "digest"
require "json"

module Logister
  class CliCursor
    class InvalidCursor < StandardError; end

    PURPOSE = "logister-cli-cursor-v1"
    VERSION = 1
    MAX_BYTES = 8_192

    class << self
      def encode(resource:, project_uuid:, filters:, timestamp:, uuid:)
        verifier.generate(
          {
            version: VERSION,
            resource: resource.to_s,
            project_uuid: project_uuid.to_s,
            filters_sha256: filters_sha256(filters),
            timestamp: timestamp.to_time.utc.iso8601(6),
            uuid: uuid.to_s
          },
          purpose: PURPOSE
        )
      end

      def decode(value, resource:, project_uuid:, filters:)
        encoded = value.to_s
        raise InvalidCursor if encoded.bytesize > MAX_BYTES

        payload = verifier.verified(encoded, purpose: PURPOSE)&.stringify_keys
        raise InvalidCursor if payload.blank?
        raise InvalidCursor unless payload["version"] == VERSION
        raise InvalidCursor unless secure_match?(payload["resource"], resource)
        raise InvalidCursor unless secure_match?(payload["project_uuid"], project_uuid)
        raise InvalidCursor unless secure_match?(payload["filters_sha256"], filters_sha256(filters))

        timestamp = Time.zone.iso8601(payload.fetch("timestamp"))
        uuid = payload.fetch("uuid").to_s
        raise InvalidCursor unless Logister::TelemetryIdentity.valid_uuid?(uuid)

        { timestamp:, uuid: }
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, KeyError, TypeError
        raise InvalidCursor
      end

      def filters_sha256(filters)
        Digest::SHA256.hexdigest(JSON.generate(canonical(filters)))
      end

      private

      def verifier
        Rails.application.message_verifier(:logister_cli_cursor)
      end

      def secure_match?(left, right)
        left = left.to_s
        right = right.to_s
        return false unless left.bytesize == right.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      def canonical(value)
        case value
        when ActionController::Parameters
          canonical(value.to_unsafe_h)
        when Hash
          value.stringify_keys.sort.to_h.transform_values { |item| canonical(item) }
        when Array
          value.map { |item| canonical(item) }
        when Time, DateTime
          value.utc.iso8601(6)
        else
          value
        end
      end
    end
  end
end
