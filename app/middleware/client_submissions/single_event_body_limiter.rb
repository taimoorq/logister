# frozen_string_literal: true

require "json"
require "stringio"
require_relative "../../services/client_submissions/request_limits"

module ClientSubmissions
  class SingleEventBodyLimiter
    MAX_BODY_BYTES = RequestLimits::MAX_WIRE_BYTES
    READ_CHUNK_BYTES = 16 * 1024
    INGEST_PATH = %r{\A/api/v1/ingest_events(?:\.json)?/?\z}

    def initialize(app, max_body_bytes: MAX_BODY_BYTES)
      @app = app
      @max_body_bytes = max_body_bytes
    end

    def call(env)
      return app.call(env) unless limited_request?(env)

      declared_length = content_length(env)
      return payload_too_large_response if declared_length && declared_length > max_body_bytes

      body = read_limited(env["rack.input"])
      return payload_too_large_response unless body

      env["rack.input"] = StringIO.new(body)
      env["CONTENT_LENGTH"] = body.bytesize.to_s
      app.call(env)
    end

    private

    attr_reader :app, :max_body_bytes

    def limited_request?(env)
      env["REQUEST_METHOD"] == "POST" && INGEST_PATH.match?(env["PATH_INFO"].to_s)
    end

    def content_length(env)
      raw_length = env["CONTENT_LENGTH"].to_s
      return if raw_length.empty?

      parsed = Integer(raw_length, 10)
      parsed unless parsed.negative?
    rescue ArgumentError
      nil
    end

    def read_limited(input)
      buffer = +"".b
      return buffer unless input

      loop do
        remaining = max_body_bytes - buffer.bytesize
        chunk = input.read([ READ_CHUNK_BYTES, remaining + 1 ].min)
        break if chunk.nil? || chunk.empty?
        return if chunk.bytesize > remaining

        buffer << chunk
      end

      buffer
    end

    def payload_too_large_response
      body = JSON.generate(
        error: "telemetry request exceeds #{max_body_bytes} bytes",
        code: "request_bytes",
        limit: max_body_bytes
      )

      [
        413,
        {
          "Content-Type" => "application/json; charset=utf-8",
          "Content-Length" => body.bytesize.to_s
        },
        [ body ]
      ]
    end
  end
end
