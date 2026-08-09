# frozen_string_literal: true

require "stringio"
require "zlib"
require "json"

class TelemetryBatchDecoder
  MAX_COMPRESSED_BYTES = ClientSubmissions::RequestLimits::MAX_WIRE_BYTES
  MAX_DECOMPRESSED_BYTES = 8.megabytes
  MAX_BATCH_EVENTS = 100
  READ_CHUNK_BYTES = 16.kilobytes
  SUPPORTED_ENCODINGS = %w[gzip identity].freeze

  class Invalid < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def self.call(...)
    new(...).call
  end

  def initialize(io:, content_encoding: nil)
    @io = io
    @content_encoding = content_encoding.to_s.downcase
  end

  def call
    validate_content_encoding!
    raw = read_limited(@io, MAX_COMPRESSED_BYTES, :compressed_bytes)
    decoded = gzip? ? decompress_limited(raw) : raw
    parse_ndjson(decoded)
  end

  private

  def gzip?
    content_encodings == [ "gzip" ]
  end

  def content_encodings
    @content_encodings ||= @content_encoding.split(",").map(&:strip).compact_blank
  end

  def validate_content_encoding!
    encodings = content_encodings
    return if encodings.empty? || encodings == [ "identity" ] || encodings == [ "gzip" ]

    unsupported = encodings - SUPPORTED_ENCODINGS
    label = unsupported.presence || encodings
    raise Invalid.new(:unsupported_encoding, "unsupported telemetry batch content encoding: #{label.join(', ')}")
  end

  def read_limited(io, limit, code)
    buffer = +"".b
    loop do
      chunk = io.read(READ_CHUNK_BYTES)
      break if chunk.blank?

      buffer << chunk
      raise Invalid.new(code, "telemetry batch exceeds #{limit} bytes") if buffer.bytesize > limit
    end
    buffer
  end

  def decompress_limited(raw)
    output = +"".b
    reader = Zlib::GzipReader.new(StringIO.new(raw))

    loop do
      chunk = reader.readpartial(READ_CHUNK_BYTES)
      output << chunk
      if output.bytesize > MAX_DECOMPRESSED_BYTES
        raise Invalid.new(:decompressed_bytes, "telemetry batch exceeds #{MAX_DECOMPRESSED_BYTES} decompressed bytes")
      end
    end
  rescue EOFError
    output
  rescue Zlib::GzipFile::Error, Zlib::Error => error
    raise Invalid.new(:invalid_gzip, "invalid gzip telemetry batch: #{error.message}")
  ensure
    reader&.close
  end

  def parse_ndjson(decoded)
    events = []
    decoded.each_line.with_index(1) do |line, line_number|
      next if line.blank?

      raise Invalid.new(:event_count, "telemetry batch exceeds #{MAX_BATCH_EVENTS} events") if events.length >= MAX_BATCH_EVENTS

      envelope = JSON.parse(line)
      unless envelope.is_a?(Hash)
        raise Invalid.new(:invalid_envelope, "telemetry batch line #{line_number} must contain an envelope object")
      end

      event = envelope["event"]
      unless event.is_a?(Hash)
        raise Invalid.new(:missing_event, "telemetry batch line #{line_number} must contain an event object")
      end

      validate_stable_identity!(event, line_number)
      TelemetryPayloadLimits.validate!(event)
      events << event
    rescue JSON::ParserError => error
      raise Invalid.new(:invalid_json, "telemetry batch line #{line_number} is invalid JSON: #{error.message}")
    end

    raise Invalid.new(:empty_batch, "telemetry batch must contain at least one event") if events.empty?

    events
  end

  def validate_stable_identity!(event, line_number)
    normalized = event.each_with_object({}) do |(key, value), values|
      values[key.to_s.underscore.downcase] = value
    end
    supplied = [ normalized["uuid"], normalized["event_id"] ].filter_map { |value| value.to_s.strip.presence }
    if supplied.empty?
      raise Invalid.new(
        :missing_identity,
        "telemetry batch line #{line_number} requires a nonblank uuid or event_id"
      )
    end

    identities = supplied.map { |value| Logister::TelemetryIdentity.normalize_uuid(value) }
    if identities.any?(&:nil?)
      raise Invalid.new(
        :invalid_identity,
        "telemetry batch line #{line_number} uuid/event_id must be a valid UUID"
      )
    end
    return if identities.uniq.one?

    raise Invalid.new(
      :conflicting_identity,
      "telemetry batch line #{line_number} uuid and event_id must identify the same envelope"
    )
  end
end
