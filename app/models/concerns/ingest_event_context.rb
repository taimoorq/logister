module IngestEventContext
  extend ActiveSupport::Concern

  class_methods do
    def duration_ms(event)
      return 0.0 unless event

      value = context_value(event, "duration_ms")
      value = context_value(event, "durationMs") if value.blank?
      value.to_f
    end

    def environment(event, default = "production")
      context_value(event, "environment").presence || default
    end

    def release(event)
      context_value(event, "release").to_s.presence
    end

    def transaction_name(event)
      context_value(event, "transaction_name").presence ||
        context_value(event, "transactionName").presence
    end

    def trace_id(event)
      context_value(event, "trace_id").presence ||
        context_value(event, "traceId").presence ||
        nested_context_value(event, "trace", "traceId").presence
    end

    def request_id(event)
      context_value(event, "request_id").presence ||
        context_value(event, "requestId").presence ||
        nested_context_value(event, "trace", "requestId").presence
    end

    def session_id(event)
      context_value(event, "session_id").presence || context_value(event, "sessionId").presence
    end

    def user_identifier(event)
      context_value(event, "user_id").presence ||
        context_value(event, "userId").presence ||
        nested_context_value(event, "user", "id").presence
    end

    private

    def context_hash(event)
      event.context.is_a?(Hash) ? event.context : {}
    end

    def context_value(event, key)
      ctx = context_hash(event)
      value = ctx[key]
      value = ctx[key.to_sym] if value.blank?
      value
    end

    def nested_context_value(event, *keys)
      current = context_hash(event)
      keys.each do |key|
        return nil unless current.is_a?(Hash)

        current = current[key] || current[key.to_sym]
      end
      current
    end
  end
end
