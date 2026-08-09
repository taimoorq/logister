# frozen_string_literal: true

require "digest"

module Logister
  class ClickhouseFailureSignature
    UUID_PATTERN = /\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/i
    ISO_TIMESTAMP_PATTERN = /\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?\b/
    ROW_POSITION_PATTERN = /\b(?:row|line)\s+\d+\b/i
    JSON_ROW_PATTERN = /\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m
    LONG_NUMBER_PATTERN = /\b\d{7,}\b/
    MAX_NORMALIZED_LENGTH = 512

    class << self
      def call(error, kind:)
        Digest::SHA256.hexdigest(
          [ kind.to_s, error.class.name, normalized_message(error.message) ].join("|")
        )[0, 24]
      end

      def normalized_message(message)
        message.to_s
          .encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
          .gsub(JSON_ROW_PATTERN, "<row>")
          .gsub(UUID_PATTERN, "<uuid>")
          .gsub(ISO_TIMESTAMP_PATTERN, "<timestamp>")
          .gsub(ROW_POSITION_PATTERN, "row <number>")
          .gsub(LONG_NUMBER_PATTERN, "<number>")
          .squish
          .first(MAX_NORMALIZED_LENGTH)
      end
    end
  end
end
