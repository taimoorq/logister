# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"
require_relative "../../../app/middleware/client_submissions/single_event_body_limiter"

RSpec.describe ClientSubmissions::SingleEventBodyLimiter do
  it "rejects an oversized declared Content-Length without reading the body or calling Rails" do
    input = spy("request body")
    app = spy("Rails application")
    middleware = described_class.new(app, max_body_bytes: 8)

    status, _headers, body = middleware.call(request_env(input: input, content_length: "9"))

    expect(input).not_to have_received(:read)
    expect(app).not_to have_received(:call)
    expect(status).to eq(413)
    expect(JSON.parse(body.join)).to include("code" => "request_bytes", "limit" => 8)
  end

  it "bounds a chunked body when Content-Length is absent" do
    app = spy("Rails application")
    middleware = described_class.new(app, max_body_bytes: 8)
    env = request_env(input: StringIO.new("123456789"), content_length: nil)
    env["HTTP_TRANSFER_ENCODING"] = "chunked"

    status, _headers, body = middleware.call(env)

    expect(app).not_to have_received(:call)
    expect(status).to eq(413)
    expect(JSON.parse(body.join).fetch("code")).to eq("request_bytes")
  end

  it "replays an accepted body for downstream JSON parsing" do
    received_body = nil
    app = lambda do |env|
      received_body = env.fetch("rack.input").read
      [ 204, {}, [] ]
    end
    middleware = described_class.new(app, max_body_bytes: 8)
    env = request_env(input: StringIO.new("12345678"), content_length: nil)

    status, = middleware.call(env)

    expect(status).to eq(204)
    expect(received_body).to eq("12345678")
    expect(env.fetch("CONTENT_LENGTH")).to eq("8")
  end

  it "leaves the separately bounded batch endpoint untouched" do
    input = spy("request body")
    app = ->(_env) { [ 204, {}, [] ] }
    middleware = described_class.new(app, max_body_bytes: 8)

    status, = middleware.call(
      request_env(path: "/api/v1/ingest_events/batch", input: input, content_length: "100")
    )

    expect(status).to eq(204)
    expect(input).not_to have_received(:read)
  end

  def request_env(input:, content_length:, path: "/api/v1/ingest_events")
    {
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => path,
      "CONTENT_LENGTH" => content_length,
      "rack.input" => input
    }
  end
end
