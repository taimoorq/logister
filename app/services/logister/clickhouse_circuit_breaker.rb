# frozen_string_literal: true

require "digest"
require "time"

module Logister
  class ClickhouseCircuitBreaker
    DEFAULT_FAILURE_THRESHOLD = 5
    DEFAULT_OPEN_SECONDS = 30
    HALF_OPEN_LEASE_SECONDS = 10

    def initialize(config: Rails.configuration.x.logister, cache: Rails.cache, clock: -> { Time.current })
      @config = config
      @cache = cache
      @clock = clock
    end

    def allow_request?
      opened_at = cached_time(opened_at_key)
      return true unless opened_at
      return false if current_time < opened_at + open_seconds

      cache.write(half_open_key, current_time.iso8601(6), expires_in: HALF_OPEN_LEASE_SECONDS, unless_exist: true) == true
    rescue StandardError => error
      warn_cache_failure("allow", error)
      true
    end

    def record_success!
      cache.delete(failure_count_key)
      cache.delete(opened_at_key)
      cache.delete(half_open_key)
      cache.delete(last_failure_key)
      true
    rescue StandardError => error
      warn_cache_failure("success", error)
      false
    end

    def record_failure!(error: nil)
      now = current_time
      failure_count = increment_failure_count
      cache.write(last_failure_key, {
        "at" => now.iso8601(6),
        "signature" => error && ClickhouseFailureSignature.call(error, kind: "request")
      }.compact, expires_in: state_ttl)

      if half_open? || failure_count >= failure_threshold
        cache.write(opened_at_key, now.iso8601(6), expires_in: state_ttl)
        cache.delete(half_open_key)
      end
      true
    rescue StandardError => cache_error
      warn_cache_failure("failure", cache_error)
      false
    end

    def status
      opened_at = cached_time(opened_at_key)
      state = if opened_at.nil?
        "closed"
      elsif current_time < opened_at + open_seconds
        "open"
      else
        "half_open"
      end

      {
        "state" => state,
        "failure_count" => cache.read(failure_count_key).to_i,
        "failure_threshold" => failure_threshold,
        "open_seconds" => open_seconds.to_i,
        "opened_at" => opened_at&.iso8601(6),
        "retry_at" => opened_at && (opened_at + open_seconds).iso8601(6),
        "probe_in_flight" => cache.exist?(half_open_key),
        "last_failure" => cache.read(last_failure_key)
      }
    rescue StandardError => error
      warn_cache_failure("status", error)
      {
        "state" => "unknown",
        "failure_threshold" => failure_threshold,
        "open_seconds" => open_seconds.to_i,
        "error_class" => error.class.name
      }
    end

    private

    attr_reader :cache

    def increment_failure_count
      cache.increment(failure_count_key, 1, expires_in: state_ttl) || begin
        cache.write(failure_count_key, 1, expires_in: state_ttl)
        1
      end
    end

    def half_open?
      cache.exist?(half_open_key) || begin
        opened_at = cached_time(opened_at_key)
        opened_at && current_time >= opened_at + open_seconds
      end
    end

    def cached_time(key)
      value = cache.read(key)
      Time.iso8601(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end

    def current_time
      @clock.call.utc
    end

    def failure_threshold
      configured = @config.clickhouse_circuit_failure_threshold if @config.respond_to?(:clickhouse_circuit_failure_threshold)
      [ Integer(configured, exception: false) || DEFAULT_FAILURE_THRESHOLD, 1 ].max
    end

    def open_seconds
      configured = @config.clickhouse_circuit_open_seconds if @config.respond_to?(:clickhouse_circuit_open_seconds)
      [ Integer(configured, exception: false) || DEFAULT_OPEN_SECONDS, 1 ].max.seconds
    end

    def state_ttl
      [ open_seconds.to_i * 20, 1.hour.to_i ].max
    end

    def namespace
      @namespace ||= Digest::SHA256.hexdigest([
        @config.respond_to?(:clickhouse_url) ? @config.clickhouse_url : nil,
        @config.respond_to?(:clickhouse_database) ? @config.clickhouse_database : nil
      ].join("|"))[0, 16]
    end

    def failure_count_key
      "logister:clickhouse:circuit:#{namespace}:failures"
    end

    def opened_at_key
      "logister:clickhouse:circuit:#{namespace}:opened_at"
    end

    def half_open_key
      "logister:clickhouse:circuit:#{namespace}:half_open"
    end

    def last_failure_key
      "logister:clickhouse:circuit:#{namespace}:last_failure"
    end

    def warn_cache_failure(operation, error)
      Rails.logger.warn("ClickHouse circuit breaker cache #{operation} failed: #{error.class} #{error.message}")
    end
  end
end
