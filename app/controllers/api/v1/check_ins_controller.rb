class Api::V1::CheckInsController < ApplicationController
  include ClientSubmissionMonitoring

  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false
  before_action :authenticate_api_key!
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  def create
    monitor_payload = check_in_params
    event = @api_key.project.ingest_events.new(
      api_key: @api_key,
      event_type: :check_in,
      level: monitor_payload[:status] == "error" ? "error" : "info",
      message: monitor_payload[:slug],
      occurred_at: monitor_payload[:occurred_at] || Time.current,
      context: {
        environment: monitor_payload[:environment],
        release: monitor_payload[:release],
        check_in_slug: monitor_payload[:slug],
        check_in_status: monitor_payload[:status],
        expected_interval_seconds: monitor_payload[:expected_interval_seconds],
        duration_ms: monitor_payload[:duration_ms],
        trace_id: monitor_payload[:trace_id],
        request_id: monitor_payload[:request_id]
      }.compact
    )

    if event.save
      CheckInMonitor.record!(project: @api_key.project, event: event)
      ClickhouseIngestJob.perform_later(event.id, request_context)
      @api_key.touch_last_used!
      render json: { id: event.uuid, status: "accepted" }, status: :created
    else
      report_client_submission_failure(
        reason: "invalid_check_in",
        status: :unprocessable_content,
        errors: event.errors.full_messages
      )
      render json: { errors: event.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def check_in_params
    payload = normalized_check_in_payload.permit(
      :slug, :status, :occurred_at, :environment, :release,
      :expected_interval_seconds, :duration_ms, :trace_id, :request_id
    )

    {
      slug: payload[:slug].to_s.strip,
      status: payload[:status].to_s.strip.presence || "ok",
      occurred_at: payload[:occurred_at].presence,
      environment: payload[:environment].to_s.strip.presence || Rails.env,
      release: payload[:release].to_s.strip.presence,
      expected_interval_seconds: payload[:expected_interval_seconds].to_i.positive? ? payload[:expected_interval_seconds].to_i : 300,
      duration_ms: payload[:duration_ms].to_f.positive? ? payload[:duration_ms].to_f : nil,
      trace_id: payload[:trace_id].to_s.strip.presence,
      request_id: payload[:request_id].to_s.strip.presence
    }
  end

  def fetch_check_in_payload
    candidates = [ params[:check_in], params[:CHECK_IN] ].compact
    raw_check_in = candidates.find { |candidate| check_in_payload_candidate?(candidate) }
    raise ActionController::ParameterMissing.new(:check_in) unless raw_check_in

    raw_check_in
  end

  def check_in_payload_candidate?(candidate)
    return false unless candidate.respond_to?(:to_unsafe_h) || candidate.respond_to?(:to_h)

    candidate_hash = candidate.respond_to?(:to_unsafe_h) ? candidate.to_unsafe_h : candidate.to_h
    normalized_keys = candidate_hash.keys.map { |key| key.to_s.underscore.downcase }
    (normalized_keys & %w[slug status occurred_at environment release expected_interval_seconds duration_ms trace_id request_id]).any?
  end

  def normalized_check_in_payload
    raw_check_in = fetch_check_in_payload
    unless raw_check_in.respond_to?(:to_unsafe_h) || raw_check_in.respond_to?(:to_h)
      raise ActionController::ParameterMissing.new(:check_in)
    end

    check_in_hash = raw_check_in.respond_to?(:to_unsafe_h) ? raw_check_in.to_unsafe_h : raw_check_in.to_h
    normalized = check_in_hash.each_with_object({}) do |(key, value), attrs|
      attrs[key.to_s.underscore.downcase] = value
    end

    ActionController::Parameters.new(normalized)
  end

  def request_context
    {
      ip: request.remote_ip,
      user_agent: request.user_agent
    }
  end

  def render_bad_request(error)
    report_client_submission_failure(
      reason: "missing_check_in_envelope",
      status: :bad_request,
      exception: error
    )
    render json: { error: error.message }, status: :bad_request
  end
end
