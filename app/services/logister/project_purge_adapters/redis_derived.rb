# frozen_string_literal: true

module Logister
  module ProjectPurgeAdapters
    class RedisDerived
      DERIVED_CACHE_MAX_TTL_SECONDS = 15.minutes.to_i

      def initialize(project_purge:, cache: Rails.cache)
        @project_purge = project_purge
        @cache = cache
      end

      def call
        patterns = [
          "project/#{@project_purge.source_project_id}/*",
          "project/#{@project_purge.project_uuid}/*"
        ]
        deleted = []

        unless @cache.respond_to?(:delete_matched)
          return {
            status: "awaiting_external",
            cache_store: @cache.class.name,
            reason: "Cache adapter cannot enumerate and verify project-derived keys",
            patterns: patterns,
            sidekiq_redis_touched: false
          }
        end

        patterns.each do |pattern|
          deleted << { "pattern" => pattern, "result" => @cache.delete_matched(pattern) }
        end
        verification = patterns.map do |pattern|
          { "pattern" => pattern, "remaining_deleted" => @cache.delete_matched(pattern) }
        end
        unless verification.all? { |entry| empty_delete_result?(entry.fetch("remaining_deleted")) }
          raise "Project cache keys were recreated during final Redis verification"
        end

        {
          status: "completed",
          cache_store: @cache.class.name,
          direct_project_namespaces: deleted,
          direct_project_namespaces_verified_absent: true,
          verification: verification,
          aggregate_cache_verification: "time_bounded",
          aggregate_cache_max_ttl_seconds: DERIVED_CACHE_MAX_TTL_SECONDS,
          sidekiq_redis_touched: false
        }
      end


      private

      def empty_delete_result?(result)
        result.nil? || result == false || result == 0 || (result.respond_to?(:empty?) && result.empty?)
      end
    end
  end
end
