# frozen_string_literal: true

require "digest"

module Logister
  module TelemetryIdentity
    UUID_PATTERN = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i

    module_function

    def valid_uuid?(value)
      UUID_PATTERN.match?(value.to_s)
    end

    def normalize_uuid(value)
      value.to_s.strip.downcase if valid_uuid?(value.to_s.strip)
    end

    def for_span(project_id:, trace_id:, span_id:)
      deterministic_uuid("logister:span:#{project_id}:#{trace_id}:#{span_id}")
    end

    def deterministic_uuid(value)
      hex = Digest::SHA256.hexdigest(value.to_s)[0, 32]
      hex[12] = "5"
      hex[16] = ((hex[16].to_i(16) & 0x3) | 0x8).to_s(16)
      [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
    end
  end
end
