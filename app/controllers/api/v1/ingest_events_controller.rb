class Api::V1::IngestEventsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false
  before_action :authenticate_api_key!

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
      render json: { errors: event.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def authenticate_api_key!
    token = bearer_token || request.headers["X-Api-Key"]
    @api_key = ApiKey.authenticate(token)

    render json: { error: "Unauthorized" }, status: :unauthorized unless @api_key
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    return nil unless header.start_with?("Bearer ")

    header.delete_prefix("Bearer ").strip
  end

  def event_params
    raw_event = params.require(:event)
    permitted = raw_event.permit(:event_type, :level, :message, :fingerprint, :occurred_at)
    raw_context = raw_event[:context]
    context_hash = raw_context.is_a?(ActionController::Parameters) ? raw_context.to_unsafe_h : (raw_context || {})
    permitted[:context] = context_hash.deep_stringify_keys
    normalize_event_payload(permitted)
  end

  def normalize_event_payload(permitted)
    context = permitted[:context].is_a?(Hash) ? permitted[:context].deep_dup : {}
    raw_event = params.require(:event)

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
    permitted[:context] = context
    permitted
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
end
