require "json"

module Logister
  class SpanIngestor
    def initialize(span:, request_context: {}, clickhouse_client: nil)
      @span = span
      @request_context = request_context
      @owns_clickhouse_client = clickhouse_client.nil?
      @clickhouse_client = clickhouse_client || ClickhouseClient.new
    end

    def call
      return unless projectable?

      # Keep rolling-deploy single-row jobs behind the same durable purge fence
      # as the batched projector and maintenance backfills.
      Project.transaction(requires_new: true) do
        project = Project.lock.find_by(id: @span.project_id)
        next if project.nil? || project.purge_pending?

        @clickhouse_client.insert_span!(attributes)
      end
    ensure
      close_owned_clickhouse_client
    end

    def projectable?
      @clickhouse_client.enabled?
    end

    def attributes
      {
        span_id: @span.uuid,
        project_id: @span.project_id,
        api_key_id: @span.api_key_id,
        projection_version: projection_version,
        identity_checksum: identity_checksum,
        trace_id: @span.trace_id,
        external_span_id: @span.span_id,
        parent_span_id: @span.parent_span_id.to_s,
        name: @span.name,
        kind: @span.kind,
        status: @span.status.to_s,
        duration_ms: @span.duration_ms.to_f,
        started_at: clickhouse_timestamp(@span.started_at),
        ended_at: @span.ended_at ? clickhouse_timestamp(@span.ended_at) : nil,
        received_at: clickhouse_timestamp(@span.created_at || @span.started_at),
        environment: context_value("environment", Rails.env),
        service: context_value("service", @span.project.slug),
        release: context_value("release", ""),
        route: route_name,
        request_id: context_value("request_id", ""),
        http_method: context_value("http_method", context_value("method", "")).to_s,
        http_status_code: http_status_code,
        is_root: @span.parent_span_id.blank? ? 1 : 0,
        tags: normalized_tags,
        context_json: @span.context.to_json,
        ip: request_ip,
        user_agent: request_user_agent
      }
    end

    private

    def close_owned_clickhouse_client
      @clickhouse_client.close if @owns_clickhouse_client
    rescue StandardError => error
      Rails.logger.warn("clickhouse_span_client_close_error error=#{error.class}: #{error.message}")
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

    def http_status_code
      raw = context_value("http_status_code", context_value("status_code", nil))
      value = Integer(raw, exception: false)
      value if value&.between?(100, 999)
    end

    def projection_version
      timestamp = @span.updated_at || @span.created_at || @span.started_at
      (timestamp.to_r * 1_000_000).to_i
    end

    def identity_checksum
      @span.uuid.to_s.delete("-").to_i(16)
    end

    def clickhouse_timestamp(value)
      value.utc.strftime("%Y-%m-%d %H:%M:%S.%3N")
    end
  end
end
