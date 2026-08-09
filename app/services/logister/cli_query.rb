# frozen_string_literal: true

module Logister
  class CliQuery
    MAX_RELATIVE_SECONDS = 5.years.to_i

    class InvalidParameter < StandardError
      attr_reader :parameter

      def initialize(message, parameter: nil)
        @parameter = parameter
        super(message)
      end
    end

    class << self
      def time(value, parameter:)
        return if value.blank?

        Time.zone.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        raise InvalidParameter.new("#{parameter} must be an ISO 8601 timestamp", parameter:)
      end

      def relative_or_time(value, parameter:)
        return if value.blank?

        raw = value.to_s.strip
        match = raw.match(/\A(\d+)(m|h|d|w)\z/)
        return time(raw, parameter:) unless match

        amount = match[1].to_i
        raise InvalidParameter.new("#{parameter} is outside the supported range", parameter:) unless amount.positive?

        seconds_per_unit = { "m" => 1.minute.to_i, "h" => 1.hour.to_i, "d" => 1.day.to_i, "w" => 1.week.to_i }.fetch(match[2])
        if amount > MAX_RELATIVE_SECONDS / seconds_per_unit
          raise InvalidParameter.new("#{parameter} is outside the supported range", parameter:)
        end

        (amount * seconds_per_unit).seconds.ago
      end

      def range(since_value:, until_value:, default_duration:, max_duration:, now: Time.current)
        finish = time(until_value, parameter: "until") || now
        start = relative_or_time(since_value, parameter: "since") || (finish - default_duration)
        raise InvalidParameter.new("since must be before until", parameter: "since") unless start < finish
        if finish - start > max_duration
          raise InvalidParameter.new("requested range exceeds #{max_duration.inspect}", parameter: "since")
        end

        [ start, finish ]
      end

      def integer(value, parameter:, default:, min:, max:)
        return default if value.blank?

        parsed = Integer(value, exception: false)
        unless parsed&.between?(min, max)
          raise InvalidParameter.new("#{parameter} must be between #{min} and #{max}", parameter:)
        end

        parsed
      end

      def decimal(value, parameter:, min: 0, max: Float::INFINITY)
        return if value.blank?

        parsed = Float(value)
        unless parsed.finite? && parsed.between?(min, max)
          raise InvalidParameter.new("#{parameter} must be between #{min} and #{max}", parameter:)
        end

        parsed
      rescue ArgumentError, TypeError
        raise InvalidParameter.new("#{parameter} must be numeric", parameter:)
      end

      def text(value, parameter:, max:)
        return if value.blank?

        normalized = value.to_s.strip
        if normalized.length > max
          raise InvalidParameter.new("#{parameter} must be at most #{max} characters", parameter:)
        end

        normalized.presence
      end

      def enum(value, parameter:, allowed:, allow_all: false)
        return if value.blank?

        normalized = value.to_s.strip
        return normalized if allow_all && normalized == "all"
        return normalized if allowed.include?(normalized)

        raise InvalidParameter.new("#{parameter} must be one of: #{allowed.join(', ')}", parameter:)
      end
    end
  end
end
