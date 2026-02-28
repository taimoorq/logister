require "logger"

module Logister
  class RequestSubscriber
    IGNORED_SQL_NAMES = %w[SCHEMA TRANSACTION].freeze

    class << self
      def install!
        return if @installed

        ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, _started, _finished, _id, payload|
          handle_process_action(payload)
        end

        ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, started, finished, _id, payload|
          handle_sql_breadcrumb(started, finished, payload)
        end

        @installed = true
      end

      private

      def handle_process_action(payload)
        return unless payload.is_a?(Hash)

        request_id = payload[:request_id].to_s.presence
        return unless request_id

        Logister::ContextStore.store_request_summary(
          request_id,
          {
            status: payload[:status],
            format: payload[:format].to_s.presence,
            method: payload[:method].to_s.presence,
            path: payload[:path].to_s.presence,
            controller: payload[:controller].to_s.presence,
            action: payload[:action].to_s.presence,
            dbRuntimeMs: numeric(payload[:db_runtime]),
            viewRuntimeMs: numeric(payload[:view_runtime]),
            allocations: payload[:allocations]
          }.compact
        )

        Logister.add_breadcrumb(
          category: "request",
          message: "#{payload[:controller]}##{payload[:action]} completed",
          data: {
            status: payload[:status],
            method: payload[:method],
            path: payload[:path],
            dbRuntimeMs: numeric(payload[:db_runtime]),
            viewRuntimeMs: numeric(payload[:view_runtime])
          }.compact
        )
      rescue StandardError => e
        logger.warn("logister request subscriber (process_action) failed: #{e.class} #{e.message}")
      end

      def handle_sql_breadcrumb(started, finished, payload)
        config = configuration
        return unless config&.capture_sql_breadcrumbs
        return unless payload.is_a?(Hash)
        return if payload[:cached]
        return if IGNORED_SQL_NAMES.include?(payload[:name].to_s)

        duration_ms = ((finished - started) * 1000.0).round(2)
        return if duration_ms < config.sql_breadcrumb_min_duration_ms.to_f

        sql_name = payload[:name].to_s.presence || "SQL"
        Logister.add_breadcrumb(
          category: "db",
          message: "#{sql_name} query",
          data: {
            durationMs: duration_ms,
            sql: payload[:sql].to_s[0, 250]
          }
        )
      rescue StandardError => e
        logger.warn("logister request subscriber (sql breadcrumb) failed: #{e.class} #{e.message}")
      end

      def numeric(value)
        return nil if value.nil?

        value.to_f.round(2)
      end

      def configuration
        return nil unless Logister.respond_to?(:configuration)

        Logister.configuration
      rescue StandardError
        nil
      end

      def logger
        configuration&.logger || Logger.new($stdout)
      rescue StandardError
        Logger.new($stdout)
      end
    end
  end
end
