# frozen_string_literal: true

require "active_support/isolated_execution_state"

module Logister
  class SelfReportingGuard
    STATE_KEY = :logister_self_reporting_suppressed
    REPORTING_PATHS = %w[
      /api/v1/ingest_events
      /api/v1/check_ins
      /api/v1/deployments
    ].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless self.class.reporting_path?(env["PATH_INFO"])

      self.class.suppress { @app.call(env) }
    end

    class << self
      def suppress
        previous = ActiveSupport::IsolatedExecutionState[STATE_KEY]
        ActiveSupport::IsolatedExecutionState[STATE_KEY] = true
        if Logister.respond_to?(:suppress_reporting)
          Logister.suppress_reporting { yield }
        else
          yield
        end
      ensure
        ActiveSupport::IsolatedExecutionState[STATE_KEY] = previous
      end

      def suppressed?
        ActiveSupport::IsolatedExecutionState[STATE_KEY] == true ||
          (Logister.respond_to?(:reporting_suppressed?) && Logister.reporting_suppressed?)
      end

      def reporting_path?(path)
        value = path.to_s

        REPORTING_PATHS.any? do |reporting_path|
          value == reporting_path || value.start_with?("#{reporting_path}/")
        end
      end
    end
  end
end
