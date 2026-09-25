# frozen_string_literal: true

# Request memoization plus short-lived caching of expensive telemetry aggregates.
# Mutable configuration/status is only memoized within its request. Background
# work and direct service callers always read fresh data.
class ProjectReadCache < ActiveSupport::CurrentAttributes
  attribute :values
  SUMMARY_TTL = 30.seconds

  class << self
    def fetch(project, key, shared: false, &block)
      return block.call unless values

      cache_key = [ "project_read_v1", project.cache_key_with_version, key ]
      return values[cache_key] if values.key?(cache_key)

      values[cache_key] = shared ? fetch_shared(cache_key, &block) : block.call
    end

    private

    def fetch_shared(key, &block)
      computing = false
      computed = false
      result = nil
      Rails.cache.fetch(key, expires_in: SUMMARY_TTL) do
        computing = true
        result = block.call
        computing = false
        computed = true
        result
      end
    rescue StandardError => error
      raise if computing

      Rails.logger.warn("Project summary cache unavailable: #{error.class}")
      computed ? result : block.call
    end
  end
end
