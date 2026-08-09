# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../../app/middleware/client_submissions/pre_auth_ip_guard"

RSpec.describe ClientSubmissions::PreAuthIpGuard do
  Result = Data.define(:limited, :limit, :remaining, :reset_at, :retry_after, :window_seconds) do
    def limited?
      limited
    end
  end

  it "rejects a limited source before calling the Rails application" do
    app = spy("Rails application")
    limiter = instance_double("ClientSubmissions::RateLimiter")
    result = Result.new(
      limited: true,
      limit: 2,
      remaining: 0,
      reset_at: 1234,
      retry_after: 30,
      window_seconds: 60
    )
    allow(limiter).to receive(:check).and_return(result)

    status, headers, body = described_class.new(app, rate_limiter: limiter, limit: 2, period: 60).call(
      request_env(path: "/api/v1/ingest_events", ip: "203.0.113.8")
    )

    expect(app).not_to have_received(:call)
    expect(limiter).to have_received(:check).with(
      identity: "ip:203.0.113.8",
      kind: "pre_auth",
      endpoint: "public_submission",
      limit: 2,
      period: 60
    )
    expect(status).to eq(429)
    expect(headers).to include(
      "Retry-After" => "30",
      "X-RateLimit-Limit" => "2",
      "X-RateLimit-Remaining" => "0",
      "X-RateLimit-Reset" => "1234"
    )
    expect(JSON.parse(body.join)).to include("error" => "Rate limit exceeded", "limit" => 2)
  end

  it "uses one coarse IP guard across every public submission endpoint" do
    app = ->(_env) { [ 204, {}, [] ] }
    limiter = instance_double("ClientSubmissions::RateLimiter")
    allowed = Result.new(
      limited: false,
      limit: 10,
      remaining: 9,
      reset_at: 1234,
      retry_after: 30,
      window_seconds: 60
    )
    allow(limiter).to receive(:check).and_return(allowed)
    middleware = described_class.new(app, rate_limiter: limiter, limit: 10, period: 60)

    middleware.call(request_env(path: "/api/v1/ingest_events/batch", ip: "198.51.100.4"))
    middleware.call(request_env(path: "/api/v1/check_ins", ip: "198.51.100.4"))

    expect(limiter).to have_received(:check).with(
      hash_including(kind: "pre_auth", endpoint: "public_submission")
    ).twice
  end

  it "does not guard unrelated routes or non-POST requests" do
    app = ->(_env) { [ 204, {}, [] ] }
    limiter = instance_double("ClientSubmissions::RateLimiter")
    allow(limiter).to receive(:check)
    middleware = described_class.new(app, rate_limiter: limiter, limit: 1, period: 60)

    expect(middleware.call(request_env(path: "/up"))).to start_with(204)
    expect(middleware.call(request_env(path: "/api/v1/ingest_events", method: "GET"))).to start_with(204)
    expect(limiter).not_to have_received(:check)
  end

  def request_env(path:, ip: "127.0.0.1", method: "POST")
    {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "REMOTE_ADDR" => ip
    }
  end
end
