# frozen_string_literal: true

class Api::V1::DeploymentsController < ApplicationController
  include ClientSubmissionMonitoring
  include Api::V1::TelemetryEnvelopeErrors

  skip_before_action :verify_authenticity_token
  skip_before_action :require_modern_browser, raise: false
  before_action :authenticate_api_key!
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  def create
    result = ProjectDeploymentIndexer.from_payload(project: @api_key.project, payload: deployment_payload)

    if result.indexed?
      @api_key.touch_last_used!
      render json: { id: result.deployment.uuid, legacy_id: result.deployment.id, status: "accepted" }, status: :created
    else
      report_client_submission_failure(
        reason: "invalid_deployment",
        status: :unprocessable_content,
        errors: result.errors
      )
      render json: { errors: result.errors }, status: :unprocessable_content
    end
  end

  private

  def deployment_payload
    raw_deployment = fetch_deployment_payload
    raise ActionController::ParameterMissing.new(:deployment) unless TelemetryEnvelope.hash_like?(raw_deployment)

    deployment_hash = TelemetryEnvelope.to_hash(raw_deployment, key: :deployment)
    deployment_hash.each_with_object({}) do |(key, value), attrs|
      attrs[key.to_s.underscore.downcase] = normalize_nested_payload(value)
    end
  end

  def fetch_deployment_payload
    candidates = [ params[:deployment], params[:DEPLOYMENT] ].compact
    raw_deployment = candidates.find { |candidate| deployment_payload_candidate?(candidate) }
    raise ActionController::ParameterMissing.new(:deployment) if raw_deployment.blank?

    raw_deployment
  end

  def deployment_payload_candidate?(candidate)
    return false unless TelemetryEnvelope.hash_like?(candidate)

    candidate_hash = TelemetryEnvelope.to_hash(candidate, key: :deployment)
    normalized_keys = candidate_hash.keys.map { |key| key.to_s.underscore.downcase }
    (normalized_keys & %w[release environment repository repo github_repository commit_sha sha branch deployed_at]).any?
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
      reason: "missing_deployment_envelope",
      status: :bad_request,
      exception: error
    )
    render json: { error: error.message }, status: :bad_request
  end
end
