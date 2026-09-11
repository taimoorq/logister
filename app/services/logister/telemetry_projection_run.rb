# frozen_string_literal: true

module Logister
  # Cooperative deadline: finish one bounded side effect, then yield safely.
  # No asynchronous exception may interrupt an insert/acknowledgement boundary.
  class TelemetryProjectionRun
    SYNCHRONOUS_CLAIM_LIMIT = 10

    def initialize(session:, seconds: 25, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @session, @clock = session, clock
      @deadline = @clock.call + seconds
    end

    def continue?(force: false)
      @clock.call < @deadline && @session.heartbeat(force: force)
    end

    def with_database_limits
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        original = connection.select_one(<<~SQL.squish)
          SELECT current_setting('statement_timeout') AS statement, current_setting('lock_timeout') AS lock,
            (SELECT setting::bigint FROM pg_settings WHERE name = 'statement_timeout') AS statement_ms,
            (SELECT setting::bigint FROM pg_settings WHERE name = 'lock_timeout') AS lock_ms
        SQL
        begin
          connection.execute("SET statement_timeout = #{bounded_timeout(original.fetch('statement_ms'), 5_000)}")
          connection.execute("SET lock_timeout = #{bounded_timeout(original.fetch('lock_ms'), 1_000)}")
          yield
        ensure
          connection.execute("SET statement_timeout = #{connection.quote(original.fetch('statement'))}")
          connection.execute("SET lock_timeout = #{connection.quote(original.fetch('lock'))}")
        end
      end
    end

    private

    def bounded_timeout(configured, maximum)
      configured.to_i.positive? ? [ configured.to_i, maximum ].min : maximum
    end
  end
end
