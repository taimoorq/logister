# frozen_string_literal: true

module Logister
  class CliPostgresStatementTimeout
    DEFAULT_TIMEOUT_MS = 15_000
    MIN_TIMEOUT_MS = 100
    MAX_TIMEOUT_MS = 120_000
    ENV_KEY = "LOGISTER_CLI_POSTGRES_STATEMENT_TIMEOUT_MS"

    class << self
      def call(&)
        new.call(&)
      end

      def configured_timeout_ms
        configured = Integer(ENV.fetch(ENV_KEY, DEFAULT_TIMEOUT_MS.to_s), exception: false)
        return configured if configured&.between?(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS)

        DEFAULT_TIMEOUT_MS
      end
    end

    def initialize(connection_pool: ActiveRecord::Base.connection_pool, timeout_ms: self.class.configured_timeout_ms)
      @connection_pool = connection_pool
      @timeout_ms = timeout_ms.to_i.clamp(MIN_TIMEOUT_MS, MAX_TIMEOUT_MS)
    end

    def call
      connection_pool.with_connection do |connection|
        previous_timeout = connection.select_value("SHOW statement_timeout")
        timeout_changed = false
        action_error = nil

        begin
          set_timeout(connection, "#{timeout_ms}ms")
          timeout_changed = true
          yield
        rescue StandardError => error
          action_error = error
          raise
        ensure
          restore_timeout(connection, previous_timeout, action_error:) if timeout_changed
        end
      end
    end

    private

    attr_reader :connection_pool, :timeout_ms

    def set_timeout(connection, value)
      connection.execute("SET statement_timeout = #{connection.quote(value)}")
    end

    def restore_timeout(connection, value, action_error:)
      set_timeout(connection, value)
    rescue StandardError => error
      Rails.logger.error(
        event: "cli.postgres_statement_timeout_restore_failed",
        error_class: error.class.name
      )
      raise if action_error.nil?
    end
  end
end
