class Api::V1::IngestEventsController < ApplicationController
  include ClientSubmissionMonitoring
  include Api::V1::IngestEventBatches

  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false
  before_action :authenticate_api_key!
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from TelemetryBatchDecoder::Invalid, with: :render_invalid_batch
  rescue_from TelemetryPayloadLimits::Exceeded, with: :render_payload_too_large

  def create
    raw_event = ingest_event_payload.event_hash
    return create_trace_span(raw_event) if ingest_event_payload.span_payload?(raw_event)

    attrs = ingest_event_payload.event_params(raw_event)
    return unless enforce_mobile_ingest_token_scope!(
      event_type: attrs["event_type"],
      context: attrs["context"]
    )

    result = IngestEventPersistence.new(
      project: @api_key.project,
      api_key: @api_key,
      attributes: attrs,
      request_context: request_context
    ).call
    event = result.event

    if result.duplicate?
      finalize_projection_intents(result.outbox_event)
      touch_client_submission_credential!
      render json: { id: event.uuid, legacy_id: event.id, status: "accepted", duplicate: true }, status: :ok
    elsif event.persisted?
      finalize_projection_intents(result.outbox_event)
      touch_client_submission_credential!
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

  def render_payload_too_large(error)
    report_client_submission_failure(
      reason: error.code,
      status: :content_too_large,
      exception: error
    )
    render json: {
      error: error.message,
      code: error.code,
      limit: error.limit,
      actual: error.actual
    }, status: :content_too_large
  end

  def create_trace_span(raw_event)
    attrs = ingest_event_payload.trace_span_params(raw_event)
    return unless enforce_mobile_ingest_token_scope!(
      event_type: "span",
      context: attrs[:context]
    )

    result = TraceSpanPersistence.new(
      project: @api_key.project,
      api_key: @api_key,
      attributes: attrs,
      request_context: request_context
    ).call
    span = result.span

    if span.persisted?
      finalize_projection_intents(result.outbox_event)
      touch_client_submission_credential!
      response = { id: span.uuid, legacy_id: span.id, status: "accepted", type: "span" }
      response[:duplicate] = true if result.duplicate?
      render json: response, status: result.duplicate? ? :ok : :created
    else
      report_client_submission_failure(
        reason: "invalid_span",
        status: :unprocessable_content,
        errors: span.errors.full_messages
      )
      render json: { errors: span.errors.full_messages }, status: :unprocessable_content
    end
  end

  def default_event_environment
    mobile_ingest_token? ? nil : Rails.env
  end

  def ingest_event_payload
    @ingest_event_payload ||= IngestEventPayloadNormalizer.new(
      params: params,
      default_environment: default_event_environment
    )
  end

  def request_context
    {
      ip: request.remote_ip,
      user_agent: request.user_agent
    }
  end

  def finalize_projection_intents(outbox_event)
    return unless outbox_event

    TelemetryProjectorJob.wake! if outbox_event.telemetry_deliveries.incomplete.exists?
  rescue StandardError => error
    Rails.logger.error("telemetry_projector_enqueue_error outbox_id=#{outbox_event&.id} error=#{error.class}: #{error.message}")
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
