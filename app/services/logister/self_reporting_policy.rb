# frozen_string_literal: true

module Logister
  # Applies only to this Rails application's SDK, never to customer ingestion.
  module SelfReportingPolicy
    module_function

    def apply!(config)
      config.capture_db_metrics = false
      config.capture_request_spans = false
      config.capture_sql_breadcrumbs = false
      config.deployment_endpoint = nil if config.respond_to?(:deployment_endpoint=)
      source_context = SourceContext.current
      config.before_notify = lambda do |payload|
        next false if SelfReportingGuard.suppressed?
        next false unless payload.is_a?(Hash) && (payload[:event_type] || payload["event_type"]).to_s == "error"

        SourceContext.enrich_payload(InternalTelemetry.enrich_payload(payload), source_context: source_context)
      end
      Rails.application.config.x.logister.web_request_transactions_enabled = false
    end
  end
end
