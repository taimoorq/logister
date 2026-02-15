require "digest"
require "json"
require "securerandom"

module Logister
  class EventIngestor
    def initialize(event:, request_context: {}, clickhouse_client: ClickhouseClient.new)
      @event = event
      @request_context = request_context
      @clickhouse_client = clickhouse_client
    end

    def call
      return unless @clickhouse_client.enabled?

      @clickhouse_client.insert_event!(clickhouse_attributes)
    end

    private

    def clickhouse_attributes
      {
        event_id: event_id,
        project_id: @event.project_id,
        api_key_id: @event.api_key_id,
        occurred_at: @event.occurred_at.utc.iso8601(3),
        received_at: Time.current.utc.iso8601(3),
        event_type: @event.event_type,
        level: @event.level.to_s,
        environment: context_value("environment", Rails.env),
        service: context_value("service", @event.project.slug),
        release: context_value("release", ""),
        fingerprint: @event.fingerprint.presence || fallback_fingerprint,
        message: @event.message,
        exception_class: context_value("exception_class", context_exception_class),
        transaction_name: context_value("transaction_name", ""),
        tags: normalized_tags,
        context_json: @event.context.to_json,
        ip: request_ip,
        user_agent: request_user_agent
      }
    end

    def request_ip
      @request_context[:ip].presence || "::"
    end

    def request_user_agent
      @request_context[:user_agent].to_s
    end

    def context_hash
      @event.context.is_a?(Hash) ? @event.context : {}
    end

    def context_value(key, fallback)
      value = context_hash[key]
      value = context_hash[key.to_sym] if value.blank?
      value.presence || fallback
    end

    def context_exception_class
      nested = context_hash["exception"] || context_hash[:exception]
      return "" unless nested.is_a?(Hash)

      nested["class"].to_s.presence || nested[:class].to_s
    end

    def normalized_tags
      raw_tags = context_hash["tags"] || context_hash[:tags]
      return {} unless raw_tags.is_a?(Hash)

      raw_tags.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    end

    def event_id
      explicit_id = context_value("event_id", "")
      return explicit_id if explicit_id.present?

      SecureRandom.uuid
    end

    def fallback_fingerprint
      Digest::SHA256.hexdigest([ @event.event_type, @event.message, @event.level ].join("|"))[0, 32]
    end
  end
end
