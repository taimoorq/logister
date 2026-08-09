# frozen_string_literal: true

require "digest"

module Api::V1::Cli::ReadRateLimitGuard
  extend ActiveSupport::Concern

  DEFAULT_REQUESTS = 600
  DEFAULT_PRE_AUTH_REQUESTS = 1_200
  DEFAULT_PERIOD_SECONDS = 60
  MAX_REQUESTS = 100_000
  MAX_PERIOD_SECONDS = 3_600

  private

  def enforce_cli_pre_auth_rate_limit!
    limit = configured_cli_rate_limit(
      "LOGISTER_CLI_PRE_AUTH_RATE_LIMIT_REQUESTS",
      DEFAULT_PRE_AUTH_REQUESTS,
      max: MAX_REQUESTS
    )
    period = configured_cli_rate_limit("LOGISTER_CLI_READ_RATE_LIMIT_PERIOD_SECONDS", DEFAULT_PERIOD_SECONDS, max: MAX_PERIOD_SECONDS)
    enforce_cli_rate_limit(
      identity: "ip:#{request.remote_ip.presence || 'unknown'}",
      namespace: "pre_auth",
      limit:,
      period:,
      message: "Too many CLI authentication attempts. Retry after the current window."
    )
  end

  def enforce_cli_read_rate_limit!
    return unless current_cli_access_token

    limit = configured_cli_rate_limit("LOGISTER_CLI_READ_RATE_LIMIT_REQUESTS", DEFAULT_REQUESTS, max: MAX_REQUESTS)
    period = configured_cli_rate_limit("LOGISTER_CLI_READ_RATE_LIMIT_PERIOD_SECONDS", DEFAULT_PERIOD_SECONDS, max: MAX_PERIOD_SECONDS)
    enforce_cli_rate_limit(
      identity: "token:#{current_cli_access_token.uuid}",
      namespace: "authenticated",
      limit:,
      period:,
      message: "Too many CLI read requests. Retry after the current window."
    )
  end

  def enforce_cli_rate_limit(identity:, namespace:, limit:, period:, message:)
    now = Time.current.to_i
    reset_at = ((now / period) + 1) * period
    identity_digest = Digest::SHA256.hexdigest(identity)
    key = [ "logister", "cli_read_rate_limit", "v2", namespace, period, reset_at, identity_digest ].join(":")
    count = increment_cli_read_rate_limit(key, expires_in: reset_at - now + 5)
    return unless count

    remaining = [ limit - count, 0 ].max
    response.set_header("X-RateLimit-Limit", limit.to_s)
    response.set_header("X-RateLimit-Remaining", remaining.to_s)
    response.set_header("X-RateLimit-Reset", reset_at.to_s)
    return if count <= limit

    retry_after = [ reset_at - now, 1 ].max
    response.set_header("Retry-After", retry_after.to_s)
    render json: {
      error: "Rate limited",
      code: "rate_limited",
      message:,
      retry_after:
    }, status: :too_many_requests
  end

  def configured_cli_rate_limit(name, fallback, max:)
    value = Integer(ENV.fetch(name, fallback.to_s), exception: false)
    value&.between?(1, max) ? value : fallback
  end

  def increment_cli_read_rate_limit(key, expires_in:)
    cache = Rails.application.config.x.logister.rate_limit_cache || Rails.cache
    cache.increment(key, 1, expires_in:) || cache.write(key, 1, expires_in:).then { 1 }
  rescue StandardError => error
    Rails.logger.warn("CLI read rate limiting skipped: #{error.class} #{error.message}")
    nil
  end
end
