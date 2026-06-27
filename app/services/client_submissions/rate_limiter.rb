# frozen_string_literal: true

require "digest"

module ClientSubmissions
  class RateLimiter
    Result = Data.define(:limited, :limit, :remaining, :reset_at, :retry_after, :window_seconds, :count) do
      def limited?
        limited
      end
    end

    def initialize(cache: Rails.cache)
      @cache = cache
    end

    def check(identity:, kind:, endpoint:, limit:, period:)
      limit = limit.to_i
      return nil unless limit.positive?

      period = period.to_i
      return nil unless period.positive?

      now = Time.current
      window_started_at = now.to_i / period * period
      reset_at = window_started_at + period
      count = rate_limit_count(kind, endpoint, identity, window_started_at, period)
      return nil unless count

      Result.new(
        limited: count > limit,
        limit: limit,
        remaining: [ limit - count, 0 ].max,
        reset_at: reset_at,
        retry_after: retry_after(reset_at),
        window_seconds: period,
        count: count
      )
    rescue StandardError => error
      Rails.logger.warn("public API rate limiting skipped: #{error.class} #{error.message}")
      nil
    end

    private

    attr_reader :cache

    def rate_limit_count(kind, endpoint, identity, window_started_at, period)
      cache_key = rate_limit_cache_key(kind, endpoint, identity, window_started_at)
      count = cache.increment(cache_key, 1, expires_in: period + 5)
      return count if count

      cache.write(cache_key, 1, expires_in: period + 5)
      1
    end

    def rate_limit_cache_key(kind, endpoint, identity, window_started_at)
      endpoint = kind == "auth_failure" ? "all" : endpoint
      identity_digest = Digest::SHA256.hexdigest(identity.to_s)
      "logister:public_api_rate_limit:v1:#{kind}:#{endpoint}:#{identity_digest}:#{window_started_at}"
    end

    def retry_after(reset_at)
      [ reset_at - Time.current.to_i, 1 ].max
    end
  end
end
