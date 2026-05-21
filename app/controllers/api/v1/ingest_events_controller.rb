class Api::V1::IngestEventsController < ApplicationController
  include ClientSubmissionMonitoring

  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false
  before_action :authenticate_api_key!
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  def create
    event = @api_key.project.ingest_events.new(event_params)
    event.api_key = @api_key
    event.occurred_at ||= Time.current

    if event.save
      ErrorGroupingService.call(event)
      CheckInMonitor.record!(project: @api_key.project, event: event) if event.check_in?
      ClickhouseIngestJob.perform_later(event.id, request_context)

      @api_key.touch_last_used!
      render json: { id: event.uuid, legacy_id: event.id, status: "accepted" }, status: :created
    else
      report_client_submission_failure(
        reason: "invalid_event",
        status: :unprocessable_content,
        errors: event.errors.full_messages
      )
      render json: { errors: event.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def event_params
    raw_event = fetch_event_payload
    event_hash = normalized_event_hash(raw_event).with_indifferent_access

    safe = event_hash.slice("event_type", "level", "message", "fingerprint", "occurred_at")
    raw_context = event_hash["context"] || {}
    safe["context"] = normalize_context_hash(raw_context)
    normalize_event_payload(safe, event_hash)
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

    merge_context_value!(context, "environment", raw_event[:environment], fallback: Rails.env)
    merge_context_value!(context, "release", raw_event[:release])
    merge_context_value!(context, "trace_id", raw_event[:trace_id] || raw_event[:traceId])
    merge_context_value!(context, "request_id", raw_event[:request_id] || raw_event[:requestId])
    merge_context_value!(context, "session_id", raw_event[:session_id] || raw_event[:sessionId])
    merge_context_value!(context, "user_id", raw_event[:user_id] || raw_event[:userId])
    merge_context_value!(context, "transaction_name", raw_event[:transaction_name] || raw_event[:transactionName])
    merge_context_value!(context, "duration_ms", raw_event[:duration_ms] || raw_event[:durationMs])
    merge_context_value!(context, "expected_interval_seconds", raw_event[:expected_interval_seconds])
    merge_context_value!(context, "check_in_slug", raw_event[:check_in_slug] || raw_event[:monitor_slug])
    merge_context_value!(context, "check_in_status", raw_event[:check_in_status] || raw_event[:status])

    context["environment"] ||= Rails.env
    attrs["context"] = context
    attrs
  end

  def merge_context_value!(context, key, value, fallback: nil)
    final_value = value.presence || fallback
    return if final_value.blank?
    return if context[key].present? || context[key.to_sym].present?

    context[key] = final_value
  end

  def request_context
    {
      ip: request.remote_ip,
      user_agent: request.user_agent
    }
  end

  def render_bad_request(error)
    report_client_submission_failure(
      reason: "missing_event_envelope",
      status: :bad_request,
      exception: error
    )
    render json: { error: error.message }, status: :bad_request
  end
end
