# frozen_string_literal: true

module Api::V1::TelemetryEnvelopeErrors
  extend ActiveSupport::Concern

  included do
    rescue_from TelemetryEnvelope::Invalid, with: :render_invalid_envelope
  end

  private

  def render_invalid_envelope(error)
    report_client_submission_failure(
      reason: "invalid_#{error.key}_envelope",
      status: :unprocessable_content,
      exception: error
    )
    render json: { errors: [ error.message ] }, status: :unprocessable_content
  end
end
