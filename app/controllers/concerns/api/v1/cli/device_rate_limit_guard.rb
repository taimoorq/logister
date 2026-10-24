# frozen_string_literal: true

require "digest"

module Api::V1::Cli::DeviceRateLimitGuard
  extend ActiveSupport::Concern

  CREATE_LIMIT = 30
  TOKEN_LIMIT = 120
  WINDOW = 1.minute

  included do
    before_action -> { enforce_cli_device_rate_limit!(kind: "create", limit: CREATE_LIMIT) }, only: :create
    before_action -> { enforce_cli_device_rate_limit!(kind: "token", limit: TOKEN_LIMIT) }, only: :token
  end

  private

  def enforce_cli_device_rate_limit!(kind:, limit:)
    identity = Digest::SHA256.hexdigest(request.remote_ip.to_s.presence || "unknown")
    key = [ "logister", "cli_device_rate_limit", "v1", kind, identity ].join(":")
    # A nil count means no store could count the request, so fail closed.
    count = Logister::RateLimitCounter.new.increment(key, expires_in: WINDOW, kind: "cli_device_#{kind}")
    return if count && count <= limit

    response.set_header("Retry-After", WINDOW.to_i.to_s)
    render json: {
      error: "Rate limited",
      code: "rate_limited",
      message: "Too many device authorization requests. Try again shortly.",
      retry_after: WINDOW.to_i
    }, status: :too_many_requests
  end
end
