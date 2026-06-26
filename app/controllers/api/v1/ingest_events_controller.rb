class Api::V1::IngestEventsController < ApplicationController
  include ClientSubmissionMonitoring

  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false
  before_action :authenticate_api_key!
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  def create
    raw_event = ingest_event_payload.event_hash
    return create_trace_span(raw_event) if ingest_event_payload.span_payload?(raw_event)

    attrs = ingest_event_payload.event_params(raw_event)
    return unless enforce_mobile_ingest_token_scope!(
      event_type: attrs["event_type"],
      context: attrs["context"]
    )

    event = @api_key.project.ingest_events.new(attrs)
    event.api_key = @api_key
    event.occurred_at ||= Time.current

    if event.save
      ProjectDeploymentIndexer.from_event(event)
      ErrorGroupingService.call(event)
      CheckInMonitor.record!(project: @api_key.project, event: event) if event.check_in?
      ClickhouseIngestJob.perform_later(event.id, request_context, event.occurred_at)

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

  def create_trace_span(raw_event)
    attrs = ingest_event_payload.trace_span_params(raw_event)
    return unless enforce_mobile_ingest_token_scope!(
      event_type: "span",
      context: attrs[:context]
    )

    span = @api_key.project.trace_spans.new(attrs)
    span.api_key = @api_key

    if span.save
      ClickhouseSpanIngestJob.perform_later(span.id, request_context)
      touch_client_submission_credential!
      render json: { id: span.uuid, legacy_id: span.id, status: "accepted", type: "span" }, status: :created
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

  def render_bad_request(error)
    report_client_submission_failure(
      reason: "missing_event_envelope",
      status: :bad_request,
      exception: error
    )
    render json: { error: error.message }, status: :bad_request
  end
end
