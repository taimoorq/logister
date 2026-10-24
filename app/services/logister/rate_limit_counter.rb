# frozen_string_literal: true

module Logister
  # Counts rate-limit hits in the shared store (Redis in production). When the
  # shared store raises or refuses the write, hits are counted in a bounded
  # per-process MemoryStore so limits still apply on each web process.
  #
  # #increment returns nil only when neither store could count the hit. Callers
  # must treat nil as "fail closed" and reject the request with Retry-After.
  class RateLimitCounter
    DEGRADED_EVENT = "rate_limit_degraded.logister"
    FALLBACK_STORE_SIZE = 16.megabytes
    FALLBACK_LOCK = Mutex.new

    class StoreUnavailable < StandardError; end

    class << self
      def fallback_store
        FALLBACK_LOCK.synchronize do
          @fallback_store ||= ActiveSupport::Cache::MemoryStore.new(size: FALLBACK_STORE_SIZE)
        end
      end

      def reset_fallback_store!
        FALLBACK_LOCK.synchronize { @fallback_store = nil }
      end
    end

    def initialize(store: nil, fallback_store: nil)
      @store = store
      @fallback_store = fallback_store
    end

    def increment(key, expires_in:, kind:, amount: 1)
      count_in(shared_store, key, amount, expires_in)
    rescue StandardError => error
      count_in_fallback(key, amount, expires_in, kind, error)
    end

    private

    def shared_store
      @store || Rails.application.config.x.logister.rate_limit_cache || Rails.cache
    end

    def fallback_store
      @fallback_store || self.class.fallback_store
    end

    def count_in(store, key, amount, expires_in)
      count = store.increment(key, amount, expires_in: expires_in)
      return count if count
      return amount if store.write(key, amount, expires_in: expires_in)

      raise StoreUnavailable, "#{store.class.name} did not store the rate-limit counter"
    end

    def count_in_fallback(key, amount, expires_in, kind, error)
      count = count_in(fallback_store, key, amount, expires_in)
      report_degraded(kind, error, fallback: "memory")
      count
    rescue StandardError => fallback_error
      report_degraded(kind, error, fallback: "none", fallback_error: fallback_error)
      nil
    end

    def report_degraded(kind, error, fallback:, fallback_error: nil)
      payload = {
        kind: kind.to_s,
        store: shared_store.class.name,
        error_class: error.class.name,
        fallback: fallback,
        fallback_error_class: fallback_error&.class&.name
      }.compact
      outcome = fallback == "memory" ? "using in-process fallback" : "failing closed"
      Rails.logger.warn("rate limit store unavailable for #{payload[:kind]}, #{outcome}: #{error.class} #{error.message}")
      ActiveSupport::Notifications.instrument(DEGRADED_EVENT, payload)
    rescue StandardError
      nil
    end
  end
end
