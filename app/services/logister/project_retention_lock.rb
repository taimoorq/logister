# frozen_string_literal: true

require "digest"
require "securerandom"

module Logister
  class ProjectRetentionLock
    CACHE_TTL = 6.hours

    def initialize(project_id:, dry_run:, cache: Rails.cache)
      @project_id = project_id
      @dry_run = dry_run
      @cache = cache
      @token = SecureRandom.uuid
      @backend = nil
      @connection = nil
      @acquired = false
    end

    def acquire
      return true if dry_run

      @acquired = if postgresql?
        acquire_postgres_lock
      else
        acquire_cache_lock
      end
    rescue StandardError => error
      Rails.logger.warn("project_retention.lock_unavailable project_id=#{project_id} error=#{error.class}: #{error.message}")
      false
    end

    def release
      return unless acquired

      case backend
      when :postgres
        connection.select_value("SELECT pg_advisory_unlock(#{advisory_lock_key})")
      when :cache
        cache.delete(cache_key) if cache.read(cache_key) == token
      end
    rescue StandardError => error
      Rails.logger.warn("project_retention.lock_release_failed project_id=#{project_id} error=#{error.class}: #{error.message}")
    ensure
      @acquired = false
      @backend = nil
      @connection = nil
    end

    private

    attr_reader :project_id, :dry_run, :cache, :token, :backend, :connection, :acquired

    def postgresql?
      ActiveRecord::Base.connection.adapter_name.downcase.include?("postgresql")
    end

    def acquire_postgres_lock
      @backend = :postgres
      @connection = ActiveRecord::Base.connection
      truthy?(connection.select_value("SELECT pg_try_advisory_lock(#{advisory_lock_key})"))
    end

    def acquire_cache_lock
      @backend = :cache
      truthy?(cache.write(cache_key, token, expires_in: CACHE_TTL, unless_exist: true))
    end

    def advisory_lock_key
      @advisory_lock_key ||= Digest::SHA256.digest("logister:project_retention:#{project_id}").unpack1("q>")
    end

    def cache_key
      "logister:project_retention_lock:v1:#{project_id}"
    end

    def truthy?(value)
      value == true || value.to_s == "t" || value.to_s == "true" || value.to_s == "1"
    end
  end
end
