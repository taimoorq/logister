# frozen_string_literal: true

require "digest"
require "securerandom"

module Logister
  # Session-scoped single-owner lease for a purge ledger. PostgreSQL advisory
  # locks avoid holding a row transaction open while remote stores are mutated.
  class ProjectPurgeLock
    CACHE_TTL = 2.hours
    ADVISORY_LOCK_TYPE = ActiveRecord::Type::BigInteger.new

    def initialize(project_purge_id:, cache: Rails.cache)
      @project_purge_id = project_purge_id
      @cache = cache
      @token = SecureRandom.uuid
    end

    def acquire
      @acquired = postgresql? ? acquire_postgres_lock : acquire_cache_lock
    rescue StandardError => error
      Rails.logger.warn(
        "project_purge.lock_unavailable purge_id=#{project_purge_id} error=#{error.class}: #{error.message}"
      )
      false
    end

    def release
      return unless @acquired

      if @backend == :postgres
        @connection.select_value("SELECT pg_advisory_unlock($1)", "ProjectPurgeLock", [ advisory_lock_bind ])
      elsif cache.read(cache_key) == token
        cache.delete(cache_key)
      end
    rescue StandardError => error
      Rails.logger.warn(
        "project_purge.lock_release_failed purge_id=#{project_purge_id} error=#{error.class}: #{error.message}"
      )
    ensure
      @acquired = false
      @backend = nil
      @connection = nil
    end

    private

    attr_reader :project_purge_id, :cache, :token

    def postgresql?
      ActiveRecord::Base.connection.adapter_name.downcase.include?("postgresql")
    end

    def acquire_postgres_lock
      @backend = :postgres
      @connection = ActiveRecord::Base.connection
      truthy?(@connection.select_value("SELECT pg_try_advisory_lock($1)", "ProjectPurgeLock", [ advisory_lock_bind ]))
    end

    def acquire_cache_lock
      @backend = :cache
      truthy?(cache.write(cache_key, token, expires_in: CACHE_TTL, unless_exist: true))
    end

    def advisory_lock_bind
      @advisory_lock_bind ||= ActiveRecord::Relation::QueryAttribute.new(
        "advisory_lock_key",
        Digest::SHA256.digest("logister:project_purge:#{project_purge_id}").unpack1("q>"),
        ADVISORY_LOCK_TYPE
      )
    end

    def cache_key
      "logister:project_purge_lock:v1:#{project_purge_id}"
    end

    def truthy?(value)
      value == true || value.to_s.in?(%w[t true 1])
    end
  end
end
