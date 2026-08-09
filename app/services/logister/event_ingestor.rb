require "digest"
require "json"
require "securerandom"

module Logister
  class EventIngestor
    def initialize(event:, request_context: {}, clickhouse_client: nil)
      @event = event
      @request_context = request_context
      @owns_clickhouse_client = clickhouse_client.nil?
      @clickhouse_client = clickhouse_client || ClickhouseClient.new
    end

    def call
      return unless projectable?

      # Legacy single-row jobs may still be present during a rolling deploy.
      # Use the same Project row fence as the batched projector so a tombstoned
      # project can never be reinserted after ClickHouse purge verification.
      Project.transaction(requires_new: true) do
        project = Project.lock.find_by(id: @event.project_id)
        next if project.nil? || project.purge_pending?

        @clickhouse_client.insert_event!(attributes)
      end
    ensure
      close_owned_clickhouse_client
    end

    def projectable?
      @clickhouse_client.enabled? && !suppressed?
    end

    def suppressed?
      clickhouse_monitoring_event?
    end

    def attributes
      clickhouse_attributes
    end

    def clickhouse_attributes
      {
        event_id: event_id,
        project_id: @event.project_id,
        api_key_id: @event.api_key_id,
        projection_version: projection_version,
        identity_checksum: identity_checksum,
        occurred_at: clickhouse_timestamp(@event.occurred_at),
        received_at: clickhouse_timestamp(@event.created_at || @event.occurred_at),
        event_type: normalized_event_type,
        level: @event.level.to_s,
        environment: context_value("environment", Rails.env),
        service: context_value("service", @event.project.slug),
        release: context_value("release", ""),
        fingerprint: @event.fingerprint.presence || fallback_fingerprint,
        message: @event.message,
        exception_class: context_value("exception_class", context_exception_class),
        transaction_name: context_value("transaction_name", ""),
        trace_id: IngestEvent.trace_id(@event).to_s,
        request_id: IngestEvent.request_id(@event).to_s,
        metric_name: metric_name,
        metric_value: numeric_context_value("value"),
        metric_unit: context_value("unit", ""),
        duration_ms: numeric_context_value("duration_ms", "durationMs"),
        transaction_status: @event.transaction? ? context_value("transaction_status", context_value("status", "")).to_s : "",
        log_severity: @event.log? ? @event.level.to_s : "",
        error_fingerprint: @event.error? ? (@event.fingerprint.presence || fallback_fingerprint) : "",
        check_in_slug: @event.check_in? ? context_value("check_in_slug", "").to_s : "",
        check_in_status: @event.check_in? ? context_value("check_in_status", context_value("status", "")).to_s : "",
        check_in_expected_interval_seconds: @event.check_in? ? unsigned_integer_context_value("expected_interval_seconds") : nil,
        tags: normalized_tags,
        context_json: @event.context.to_json,
        ip: request_ip,
        user_agent: request_user_agent
      }
    end

    alias_method :attributes, :clickhouse_attributes

    private

    def close_owned_clickhouse_client
      @clickhouse_client.close if @owns_clickhouse_client
    rescue StandardError => error
      Rails.logger.warn("clickhouse_event_client_close_error error=#{error.class}: #{error.message}")
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

    def metric_name
      @event.metric? ? @event.message.to_s : ""
    end

    def numeric_context_value(*keys)
      raw = keys.lazy.map { |key| context_hash[key] || context_hash[key.to_sym] }.find { |value| !value.nil? && value != "" }
      return if raw.nil?

      Float(raw)
    rescue ArgumentError, TypeError
      nil
    end

    def unsigned_integer_context_value(*keys)
      value = numeric_context_value(*keys)
      return if value.nil? || value.negative?

      value.to_i
    end

    def projection_version
      timestamp = @event.updated_at || @event.created_at || @event.occurred_at
      (timestamp.to_r * 1_000_000).to_i
    end

    def event_id
      @event.uuid
    end

    def identity_checksum
      event_id.to_s.delete("-").to_i(16)
    end

    def fallback_fingerprint
      Digest::SHA256.hexdigest([ @event.event_type, @event.message, @event.level ].join("|"))[0, 32]
    end

    def normalized_event_type
      value = @event.event_type.to_s
      return value if value.in?(%w[error metric transaction log check_in])

      "metric"
    end

    def clickhouse_monitoring_event?
      context_hash["clickhouse_ingest"].present? || context_hash[:clickhouse_ingest].present?
    end

    def clickhouse_timestamp(value)
      value.utc.strftime("%Y-%m-%d %H:%M:%S.%3N")
    end
  end
end
