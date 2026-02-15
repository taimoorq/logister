class Api::V1::IngestEventsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false
  before_action :authenticate_api_key!

  def create
    event = @api_key.project.ingest_events.new(event_params)
    event.api_key = @api_key
    event.occurred_at ||= Time.current

    if event.save
      ClickhouseIngestJob.perform_later(event.id, request_context)

      @api_key.touch_last_used!
      render json: { id: event.id, status: "accepted" }, status: :created
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
    permitted = params.require(:event).permit(:event_type, :level, :message, :fingerprint, :occurred_at)
    raw_context = params.dig(:event, :context)
    permitted[:context] = raw_context.is_a?(ActionController::Parameters) ? raw_context.to_unsafe_h : raw_context
    permitted
  end

  def request_context
    {
      ip: request.remote_ip,
      user_agent: request.user_agent
    }
  end
end
