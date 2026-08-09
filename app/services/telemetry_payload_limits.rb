# frozen_string_literal: true

class TelemetryPayloadLimits
  MAX_EVENT_BYTES = 1.megabyte
  MAX_CONTEXT_DEPTH = 16
  MAX_CONTEXT_KEYS = 512
  MAX_ARRAY_LENGTH = 1_000
  MAX_STRING_BYTES = 256.kilobytes
  MAX_MESSAGE_BYTES = 64.kilobytes

  class Exceeded < StandardError
    attr_reader :code, :limit, :actual

    def initialize(code:, limit:, actual:)
      @code = code
      @limit = limit
      @actual = actual
      super("telemetry payload #{code.to_s.tr('_', ' ')} exceeds #{limit}")
    end
  end

  def self.validate!(event)
    new(event).validate!
  end

  def initialize(event)
    @event = event.respond_to?(:to_unsafe_h) ? event.to_unsafe_h : event.to_h
    @key_count = 0
    @estimated_bytes = 0
  end

  def validate!
    validate_message!
    walk(@event, depth: 0)
    enforce!(:event_bytes, MAX_EVENT_BYTES, @estimated_bytes)
    true
  end

  private

  def validate_message!
    message = @event["message"] || @event[:message]
    return unless message.respond_to?(:bytesize)

    enforce!(:message_bytes, MAX_MESSAGE_BYTES, message.bytesize)
  end

  def walk(value, depth:)
    enforce!(:context_depth, MAX_CONTEXT_DEPTH, depth)

    case value
    when Hash
      @key_count += value.size
      enforce!(:context_keys, MAX_CONTEXT_KEYS, @key_count)
      value.each do |key, nested|
        add_bytes(key.to_s.bytesize)
        walk(nested, depth: depth + 1)
      end
    when Array
      enforce!(:array_length, MAX_ARRAY_LENGTH, value.length)
      value.each { |nested| walk(nested, depth: depth + 1) }
    when String
      enforce!(:string_bytes, MAX_STRING_BYTES, value.bytesize)
      add_bytes(value.bytesize)
    when Numeric, TrueClass, FalseClass
      add_bytes(value.to_s.bytesize)
    when NilClass
      add_bytes(4)
    else
      add_bytes(value.to_s.bytesize)
    end
  end

  def add_bytes(bytes)
    @estimated_bytes += bytes + 4
    enforce!(:event_bytes, MAX_EVENT_BYTES, @estimated_bytes)
  end

  def enforce!(code, limit, actual)
    return if actual <= limit

    raise Exceeded.new(code: code, limit: limit, actual: actual)
  end
end
