# frozen_string_literal: true

# Converts submitted ingest envelopes (`event`, `check_in`, `deployment`) and
# their nested objects into hashes. JSON arrays respond to `to_h` but raise
# TypeError unless every element is a key/value pair, so those surface as
# Invalid and the API answers 422 instead of 500.
module TelemetryEnvelope
  class Invalid < StandardError
    attr_reader :key

    def initialize(key)
      @key = key.to_s
      super("#{@key} must be a JSON object")
    end
  end

  module_function

  def hash_like?(value)
    value.respond_to?(:to_unsafe_h) || value.respond_to?(:to_h)
  end

  def to_hash(value, key:)
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    return value.to_h if value.respond_to?(:to_h)

    nil
  rescue TypeError, ArgumentError
    raise Invalid.new(key)
  end
end
