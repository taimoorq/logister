# frozen_string_literal: true

module Github
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      payload_body = request.raw_post
      verifier = WebhookSignatureVerifier.new

      return head :service_unavailable unless verifier.configured?
      return head :unauthorized unless verifier.valid?(
        payload: payload_body,
        signature: request.headers["X-Hub-Signature-256"]
      )

      InstallationSync.from_webhook(
        event: request.headers["X-GitHub-Event"],
        payload: JSON.parse(payload_body.presence || "{}")
      )
      head :accepted
    rescue JSON::ParserError
      head :bad_request
    rescue InstallationSync::Error, InstallationRepositoriesClient::Error,
           InstallationToken::Error, ActiveRecord::RecordInvalid, KeyError => error
      Rails.logger.warn("GitHub webhook sync failed: #{error.class} #{error.message}")
      head :bad_gateway
    end
  end
end
