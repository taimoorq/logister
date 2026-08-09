# frozen_string_literal: true

require "json"

module ClientSubmissions
  class PreAuthIpGuard
    ROUTES = [
      %r{\A/api/v1/ingest_events(?:\.json)?/?\z},
      %r{\A/api/v1/ingest_events/batch(?:\.json)?/?\z},
      %r{\A/api/v1/check_ins(?:\.json)?/?\z},
      %r{\A/api/v1/deployments(?:\.json)?/?\z},
      %r{\A/api/v1/mobile_ingest_tokens(?:\.json)?/?\z}
    ].freeze
    SHARED_ENDPOINT = "public_submission"

    def initialize(app, rate_limiter: nil, limit: nil, period: nil)
      @app = app
      @rate_limiter = rate_limiter
      @limit = limit
      @period = period
    end

    def call(env)
      return app.call(env) unless guarded_request?(env)

      result = limiter.check(
        identity: "ip:#{client_ip(env)}",
        kind: "pre_auth",
        endpoint: SHARED_ENDPOINT,
        limit: configured_limit,
        period: configured_period
      )
      return app.call(env) unless result&.limited?

      rate_limited_response(result)
    end

    private

    attr_reader :app, :rate_limiter, :limit, :period

    def guarded_request?(env)
      return false unless env["REQUEST_METHOD"] == "POST"

      path = env["PATH_INFO"].to_s
      ROUTES.any? { |pattern| pattern.match?(path) }
    end

    def client_ip(env)
      (env["action_dispatch.remote_ip"] || env["REMOTE_ADDR"] || "unknown").to_s
    end

    def limiter
      # Resolve the configured cache for each request. Runtime configuration and
      # tests can replace the rate-limit store after the middleware is built.
      rate_limiter || ClientSubmissions::RateLimiter.new
    end

    def configured_limit
      return limit.to_i if limit

      Project.default_public_api_pre_auth_rate_limit_requests
    end

    def configured_period
      return period.to_i if period

      Project.default_public_api_rate_limit_period_seconds
    end

    def rate_limited_response(result)
      body = JSON.generate(
        error: "Rate limit exceeded",
        limit: result.limit,
        window_seconds: result.window_seconds,
        retry_after: result.retry_after
      )
      headers = {
        "Content-Type" => "application/json; charset=utf-8",
        "Content-Length" => body.bytesize.to_s,
        "Retry-After" => result.retry_after.to_s,
        "X-RateLimit-Limit" => result.limit.to_s,
        "X-RateLimit-Remaining" => result.remaining.to_s,
        "X-RateLimit-Reset" => result.reset_at.to_s
      }

      [ 429, headers, [ body ] ]
    end
  end
end
