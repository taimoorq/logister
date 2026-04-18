class Api::V1::CheckInsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false
  before_action :authenticate_api_key!

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
      render json: { errors: event.errors.full_messages }, status: :unprocessable_content
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

  def check_in_params
    payload = params.require(:check_in).permit(
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

  def request_context
    {
      ip: request.remote_ip,
      user_agent: request.user_agent
    }
  end
end
