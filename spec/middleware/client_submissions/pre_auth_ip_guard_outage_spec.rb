# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientSubmissions::PreAuthIpGuard, "during a rate-limit store outage" do
  let(:app) { ->(_env) { [ 204, {}, [] ] } }

  it "keeps enforcing the coarse IP limit through the in-process fallback" do
    limiter = ClientSubmissions::RateLimiter.new(cache: unavailable_rate_limit_store)
    middleware = described_class.new(app, rate_limiter: limiter, limit: 1, period: 60)

    expect(middleware.call(request_env).first).to eq(204)

    status, headers, = middleware.call(request_env)
    expect(status).to eq(429)
    expect(headers["Retry-After"].to_i).to be_positive
  end

  it "fails closed before the Rails application when no store can count" do
    break_rate_limit_fallback_store!
    limiter = ClientSubmissions::RateLimiter.new(cache: unavailable_rate_limit_store)
    downstream = spy("Rails application")
    middleware = described_class.new(downstream, rate_limiter: limiter, limit: 100, period: 60)

    status, headers, = middleware.call(request_env)

    expect(status).to eq(429)
    expect(headers["Retry-After"].to_i).to be_between(1, 60)
    expect(downstream).not_to have_received(:call)
  end

  def request_env
    { "REQUEST_METHOD" => "POST", "PATH_INFO" => "/api/v1/ingest_events", "REMOTE_ADDR" => "203.0.113.8" }
  end
end
