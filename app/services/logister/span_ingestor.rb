require "json"

module Logister
  class SpanIngestor
    def initialize(span:, request_context: {}, clickhouse_client: ClickhouseClient.new)
      @span = span
      @request_context = request_context
      @clickhouse_client = clickhouse_client
    end

    def call
      return unless @clickhouse_client.enabled?

      @clickhouse_client.insert_span!(clickhouse_attributes)
    end

    private

    def clickhouse_attributes
      {
        span_id: @span.uuid,
        project_id: @span.project_id,
        api_key_id: @span.api_key_id,
        trace_id: @span.trace_id,
        external_span_id: @span.span_id,
        parent_span_id: @span.parent_span_id.to_s,
        name: @span.name,
        kind: @span.kind,
        status: @span.status.to_s,
        duration_ms: @span.duration_ms.to_f,
        started_at: @span.started_at.utc.iso8601(3),
        ended_at: @span.ended_at&.utc&.iso8601(3),
        received_at: Time.current.utc.iso8601(3),
        environment: context_value("environment", Rails.env),
        service: context_value("service", @span.project.slug),
        release: context_value("release", ""),
        route: route_name,
        request_id: context_value("request_id", ""),
        tags: normalized_tags,
        context_json: @span.context.to_json,
        ip: request_ip,
        user_agent: request_user_agent
      }
    end

    def context_hash
      @span.context.is_a?(Hash) ? @span.context : {}
    end

    def context_value(key, fallback)
      value = context_hash[key]
      value = context_hash[key.to_sym] if value.blank?
      value.presence || fallback
    end

    def route_name
      @span.route_name.to_s
    end

    def normalized_tags
      raw_tags = context_hash["tags"] || context_hash[:tags]
      return {} unless raw_tags.is_a?(Hash)

      raw_tags.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    end

    def request_ip
      @request_context[:ip].presence || "::"
    end

    def request_user_agent
      @request_context[:user_agent].to_s
    end
  end
end
