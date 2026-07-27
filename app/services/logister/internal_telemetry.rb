# frozen_string_literal: true

module Logister
  module InternalTelemetry
    CONTEXT_KEY = "logister_internal"
    NOTIFICATION_JOB_PATTERN = /(?:NotificationJob|ProjectErrorFirstOccurrenceAlertJob|ProjectErrorDigestJob|ActionMailer::MailDeliveryJob)\z/
    CLICKHOUSE_JOB_PATTERN = /Clickhouse(?:Ingest|SpanIngest)Job\z/

    module_function

    def enrich_payload(payload)
      return payload unless payload.is_a?(Hash)

      context = payload[:context] || payload["context"]
      return payload unless context.is_a?(Hash)
      return payload if context_value(context, CONTEXT_KEY).present?

      job_class = context_value(context_value(context, "job"), "jobClass").to_s
      component = component_for_job(job_class)
      return payload unless component

      context[CONTEXT_KEY] = {
        "component" => component,
        "operation" => "job_failure",
        "feedback_depth" => 1,
        "job_class" => job_class
      }
      payload
    end

    def with_origin(context, component:, operation:, caused_by: nil)
      base = context.is_a?(Hash) ? context.deep_dup : {}
      base[CONTEXT_KEY] = {
        "component" => component.to_s,
        "operation" => operation.to_s,
        "feedback_depth" => feedback_depth(caused_by) + 1,
        "caused_by_type" => caused_by&.class&.name,
        "caused_by_uuid" => caused_by.respond_to?(:uuid) ? caused_by.uuid : nil
      }.compact
      base
    end

    def component(record_or_context)
      metadata(record_or_context)["component"].to_s.presence
    end

    def feedback_depth(record_or_context)
      Integer(metadata(record_or_context)["feedback_depth"], exception: false).to_i.clamp(0, 100)
    end

    def metadata(record_or_context)
      context = if record_or_context.respond_to?(:context)
        record_or_context.context
      else
        record_or_context
      end
      return {} unless context.is_a?(Hash)

      value = context_value(context, CONTEXT_KEY)
      value.is_a?(Hash) ? value.stringify_keys : {}
    end

    def component_for_job(job_class)
      return "clickhouse" if CLICKHOUSE_JOB_PATTERN.match?(job_class)
      return "notifications" if NOTIFICATION_JOB_PATTERN.match?(job_class)

      nil
    end
    private_class_method :component_for_job

    def context_value(context, key)
      return nil unless context.respond_to?(:[])

      context[key] || context[key.to_sym]
    end
    private_class_method :context_value
  end
end
