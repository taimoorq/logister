class Api::V1::MobileIngestTokensController < ApplicationController
  include ClientSubmissionMonitoring

  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false
  before_action :authenticate_server_api_key!
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  def create
    token = @api_key.project.mobile_ingest_tokens.new(mobile_ingest_token_params)
    token.api_key = @api_key

    if token.save
      @api_key.touch_last_used!
      render json: {
        token: token.plain_token,
        expires_at: token.expires_at.iso8601,
        platform: token.platform,
        service: token.service,
        environment: token.environment,
        release: token.release,
        session_id: token.session_id,
        allowed_event_types: token.allowed_event_types
      }.compact, status: :created
    else
      report_client_submission_failure(
        reason: "invalid_mobile_ingest_token",
        status: :unprocessable_content,
        errors: token.errors.full_messages,
        api_key: @api_key
      )
      render json: { errors: token.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def mobile_ingest_token_params
    payload = normalized_mobile_ingest_token_payload
    expires_in_seconds = mobile_ingest_token_expires_in(payload[:expires_in_seconds])

    {
      platform: payload[:platform],
      service: payload[:service],
      environment: payload[:environment],
      release: payload[:release],
      session_id: payload[:session_id],
      allowed_event_types: payload[:allowed_event_types],
      expires_at: Time.current + expires_in_seconds.seconds
    }
  end

  def mobile_ingest_token_expires_in(raw_value)
    return MobileIngestToken::DEFAULT_EXPIRES_IN_SECONDS if raw_value.blank?

    Integer(raw_value)
  rescue ArgumentError, TypeError
    0
  end

  def normalized_mobile_ingest_token_payload
    raw_token = fetch_mobile_ingest_token_payload
    unless raw_token.respond_to?(:to_unsafe_h) || raw_token.respond_to?(:to_h)
      raise ActionController::ParameterMissing.new(:mobile_ingest_token)
    end

    token_hash = raw_token.respond_to?(:to_unsafe_h) ? raw_token.to_unsafe_h : raw_token.to_h
    token_hash.each_with_object({}) do |(key, value), attrs|
      attrs[key.to_s.underscore.downcase.to_sym] = normalize_nested_payload(value)
    end
  end

  def fetch_mobile_ingest_token_payload
    raw_token = params[:mobile_ingest_token] || params[:MOBILE_INGEST_TOKEN]
    raise ActionController::ParameterMissing.new(:mobile_ingest_token) if raw_token.blank?

    raw_token
  end

  def normalize_nested_payload(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), attrs|
        attrs[key.to_s.underscore.downcase] = normalize_nested_payload(nested_value)
      end
    when Array
      value.map { |nested_value| normalize_nested_payload(nested_value) }
    else
      value
    end
  end

  def render_bad_request(error)
    report_client_submission_failure(
      reason: "missing_mobile_ingest_token_envelope",
      status: :bad_request,
      exception: error
    )
    render json: { error: error.message }, status: :bad_request
  end
end
