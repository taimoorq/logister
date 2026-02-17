module Logister
  class SqlSubscriber
    IGNORED_SQL_NAMES = %w[SCHEMA TRANSACTION].freeze

    class << self
      def install!
        return if @installed

        ActiveSupport::Notifications.subscribe('sql.active_record') do |name, started, finished, _id, payload|
          handle_sql_event(name, started, finished, payload)
        end

        @installed = true
      end

      private

      def handle_sql_event(_name, started, finished, payload)
        config = Logister.configuration
        return unless config.capture_db_metrics
        return if payload[:cached]
        return if IGNORED_SQL_NAMES.include?(payload[:name].to_s)

        duration_ms = (finished - started) * 1000.0
        return if duration_ms < config.db_metric_min_duration_ms.to_f
        return if sampled_out?(config.db_metric_sample_rate)

        level = duration_ms >= 500 ? 'warn' : 'info'

        Logister.report_metric(
          message: 'db.query',
          level: level,
          context: {
            duration_ms: duration_ms.round(2),
            name: payload[:name].to_s,
            sql: payload[:sql].to_s,
            cached: false,
            binds_count: Array(payload[:binds]).size
          },
          tags: {
            category: 'database'
          }
        )
      rescue StandardError => e
        config.logger.warn("logister sql subscriber failed: #{e.class} #{e.message}")
      end

      def sampled_out?(sample_rate)
        rate = sample_rate.to_f
        return true if rate <= 0.0
        return false if rate >= 1.0

        rand > rate
      end
    end
  end
end
