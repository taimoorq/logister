# frozen_string_literal: true

require "digest"

module Logister
  class RailsRequestPerformanceReporter
    LOG_MESSAGE = "Slow Rails request"
    PARAM_KEYS_TO_SKIP = %w[action controller authenticity_token commit utf8].freeze
    TAGS = { category: "web_performance", source: "rails" }.freeze

    class << self
      def install!
        return if @installed

        ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, _started, _finished, _id, payload|
          call(payload)
        end

        @installed = true
      end

      def call(payload)
        return unless enabled?
        return unless payload.is_a?(Hash)

        duration_ms = numeric(payload[:duration])
        return unless duration_ms
        return if duration_ms < min_duration_ms

        context = request_context(payload, duration_ms)
        transaction_name = "#{context[:method]} #{context[:route]}".strip

        Logister.report_transaction(
          name: transaction_name,
          duration_ms: duration_ms,
          level: duration_ms >= log_min_duration_ms ? "warn" : "info",
          status: context[:status],
          fingerprint: fingerprint("rails-request-transaction:#{transaction_name}"),
          context: context,
          tags: TAGS
        )

        report_slow_log(context) if duration_ms >= log_min_duration_ms
      rescue StandardError => e
        logger.warn("logister rails request performance reporter failed: #{e.class} #{e.message}")
      end

      private

      def request_context(payload, duration_ms)
        db_runtime_ms = numeric(payload[:db_runtime])
        view_runtime_ms = numeric(payload[:view_runtime])
        app_runtime_ms = app_runtime(duration_ms, db_runtime_ms, view_runtime_ms)
        controller = payload[:controller].to_s
        action = payload[:action].to_s
        route = [ controller, action ].reject(&:blank?).join("#")

        {
          route: route.presence || payload[:path].to_s,
          controller: controller.presence,
          action: action.presence,
          method: payload[:method].to_s.presence,
          path: payload[:path].to_s.presence,
          format: payload[:format].to_s.presence,
          status: integer(payload[:status]),
          duration_ms: duration_ms,
          db_runtime_ms: db_runtime_ms,
          view_runtime_ms: view_runtime_ms,
          app_runtime_ms: app_runtime_ms,
          allocations: integer(payload[:allocations]),
          param_keys: parameter_keys(payload[:params])
        }.compact
      end

      def report_slow_log(context)
        Logister.report_log(
          message: LOG_MESSAGE,
          level: "warn",
          fingerprint: fingerprint("rails-request-log:#{context[:route]}"),
          context: context,
          tags: TAGS
        )
      end

      def app_runtime(duration_ms, db_runtime_ms, view_runtime_ms)
        other_runtime = duration_ms.to_f - db_runtime_ms.to_f - view_runtime_ms.to_f
        return nil if other_runtime.negative?

        other_runtime.round(2)
      end

      def parameter_keys(params)
        return [] unless params.respond_to?(:keys)

        params.keys
              .map(&:to_s)
              .reject { |key| PARAM_KEYS_TO_SKIP.include?(key) }
              .sort
      end

      def numeric(value)
        return nil if value.nil?

        value.to_f.round(2)
      end

      def integer(value)
        return nil if value.nil?

        Integer(value, exception: false)
      end

      def fingerprint(value)
        Digest::SHA256.hexdigest(value)[0, 32]
      end

      def min_duration_ms
        logister_config.web_request_min_duration_ms.to_f
      end

      def log_min_duration_ms
        logister_config.web_request_log_min_duration_ms.to_f
      end

      def enabled?
        logister_config.web_request_transactions_enabled != false
      end

      def logister_config
        Rails.application.config.x.logister
      end

      def logger
        Logister.configuration.logger
      rescue StandardError
        Rails.logger
      end
    end
  end
end
