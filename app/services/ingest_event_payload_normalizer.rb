# frozen_string_literal: true

class IngestEventPayloadNormalizer
  def initialize(params:, default_environment:)
    @params = params
    @default_environment = default_environment
  end

  def event_hash
    raw_event = fetch_event_payload
    normalized_event_hash(raw_event).with_indifferent_access
  end

  def span_payload?(event_hash)
    event_hash["event_type"].to_s == "span"
  end

  def event_params(event_hash)
    safe = event_hash.slice("event_type", "level", "message", "fingerprint", "occurred_at")
    raw_context = event_hash["context"] || {}
    safe["context"] = normalize_context_hash(raw_context)
    normalize_event_payload(safe, event_hash)
  end

  def trace_span_params(event_hash)
    context = normalize_context_hash(event_hash["context"] || {})
    normalized = normalize_span_payload(event_hash, context)

    {
      trace_id: normalized.fetch("trace_id"),
      span_id: normalized.fetch("span_id"),
      parent_span_id: normalized["parent_span_id"],
      name: normalized.fetch("name"),
      kind: normalized["kind"],
      status: normalized["status"],
      duration_ms: normalized["duration_ms"],
      started_at: normalized["started_at"],
      ended_at: normalized["ended_at"],
      context: context
    }
  end

  private

  attr_reader :params, :default_environment

  def normalize_span_payload(event_hash, context)
    normalized = {
      "trace_id" => first_present(
        event_hash[:trace_id], event_hash[:traceId], context["trace_id"], context["traceId"],
        context.dig("trace", "traceId")
      ),
      "span_id" => first_present(
        event_hash[:span_id], event_hash[:spanId], context["span_id"], context["spanId"],
        context.dig("trace", "spanId")
      ),
      "parent_span_id" => first_present(
        event_hash[:parent_span_id], event_hash[:parentSpanId],
        context["parent_span_id"], context["parentSpanId"],
        context.dig("trace", "parentSpanId")
      ),
      "name" => first_present(event_hash[:name], event_hash[:message], context["name"], context["span_name"], "span"),
      "kind" => first_present(event_hash[:kind], event_hash[:span_kind], event_hash[:spanKind], context["kind"], context["span_kind"], context["spanKind"], "internal"),
      "status" => first_present(event_hash[:status], context["status"]),
      "duration_ms" => numeric_duration(first_present(event_hash[:duration_ms], event_hash[:durationMs], context["duration_ms"], context["durationMs"])),
      "started_at" => parse_timestamp(first_present(event_hash[:started_at], event_hash[:startedAt], event_hash[:occurred_at], context["started_at"], context["startedAt"], Time.current)),
      "ended_at" => parse_optional_timestamp(first_present(event_hash[:ended_at], event_hash[:endedAt], context["ended_at"], context["endedAt"]))
    }

    context["trace_id"] ||= normalized["trace_id"]
    context["span_id"] ||= normalized["span_id"]
    context["parent_span_id"] ||= normalized["parent_span_id"] if normalized["parent_span_id"].present?
    context["span_kind"] ||= normalized["kind"]
    context["duration_ms"] ||= normalized["duration_ms"]
    context["environment"] ||= first_present(event_hash[:environment], context["environment"], default_environment)
    context["release"] ||= first_present(event_hash[:release], context["release"])
    context["service"] ||= first_present(event_hash[:service], context["service"])
    context["request_id"] ||= first_present(event_hash[:request_id], event_hash[:requestId], context["request_id"], context["requestId"])
    context["transaction_name"] ||= first_present(event_hash[:transaction_name], event_hash[:transactionName], context["transaction_name"], context["transactionName"])

    normalized
  end

  def fetch_event_payload
    raw_event = params[:event] || params[:EVENT]
    raise ActionController::ParameterMissing.new(:event) if raw_event.blank?

    raw_event
  end

  def normalized_event_hash(raw_event)
    unless raw_event.respond_to?(:to_unsafe_h) || raw_event.respond_to?(:to_h)
      raise ActionController::ParameterMissing.new(:event)
    end

    event_hash = raw_event.respond_to?(:to_unsafe_h) ? raw_event.to_unsafe_h : raw_event.to_h

    event_hash.each_with_object({}) do |(key, value), normalized|
      normalized[normalize_payload_key(key)] = value
    end
  end

  def normalize_payload_key(key)
    key.to_s.underscore.downcase
  end

  def normalize_context_hash(raw_context)
    context_hash =
      if raw_context.respond_to?(:to_unsafe_h)
        raw_context.to_unsafe_h
      elsif raw_context.respond_to?(:to_h)
        raw_context.to_h
      else
        {}
      end

    add_normalized_context_keys(context_hash)
  end

  def add_normalized_context_keys(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), normalized|
        string_key = key.to_s
        normalized_value = add_normalized_context_keys(nested_value)
        normalized[string_key] = normalized_value

        normalized_key = normalize_payload_key(key)
        normalized[normalized_key] = normalized_value unless normalized.key?(normalized_key)
      end
    when Array
      value.map { |nested_value| add_normalized_context_keys(nested_value) }
    else
      value
    end
  end

  def normalize_event_payload(attrs, raw_event)
    context = attrs["context"].is_a?(Hash) ? attrs["context"].deep_dup : {}

    merge_context_value!(context, "environment", raw_event[:environment], fallback: default_environment)
    merge_context_value!(context, "release", raw_event[:release])
    merge_context_value!(context, "trace_id", raw_event[:trace_id] || raw_event[:traceId])
    merge_context_value!(context, "request_id", raw_event[:request_id] || raw_event[:requestId])
    merge_context_value!(context, "session_id", raw_event[:session_id] || raw_event[:sessionId])
    merge_context_value!(context, "user_id", raw_event[:user_id] || raw_event[:userId])
    merge_context_value!(context, "commit_sha", raw_event[:commit_sha] || raw_event[:commitSha] || raw_event[:sha])
    merge_context_value!(context, "repository", raw_event[:repository] || raw_event[:repo] || raw_event[:github_repository] || raw_event[:githubRepository])
    merge_context_value!(context, "branch", raw_event[:branch])
    merge_context_value!(context, "transaction_name", raw_event[:transaction_name] || raw_event[:transactionName])
    merge_context_value!(context, "duration_ms", raw_event[:duration_ms] || raw_event[:durationMs])
    merge_context_value!(context, "expected_interval_seconds", raw_event[:expected_interval_seconds])
    merge_context_value!(context, "check_in_slug", raw_event[:check_in_slug] || raw_event[:monitor_slug])
    merge_context_value!(context, "check_in_status", raw_event[:check_in_status] || raw_event[:status])

    context["environment"] ||= default_environment if default_environment.present?
    attrs["context"] = context
    attrs
  end

  def merge_context_value!(context, key, value, fallback: nil)
    final_value = value.presence || fallback
    return if final_value.blank?
    return if context[key].present? || context[key.to_sym].present?

    context[key] = final_value
  end

  def first_present(*values)
    values.find(&:present?)
  end

  def numeric_duration(value)
    value.to_f.positive? ? value.to_f : 0.0
  end

  def parse_timestamp(value)
    return value if value.is_a?(Time)
    return value.to_time if value.respond_to?(:to_time) && !value.is_a?(String)

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    Time.current
  end

  def parse_optional_timestamp(value)
    return if value.blank?

    parse_timestamp(value)
  end
end
