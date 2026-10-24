# frozen_string_literal: true

require "digest"

# Limits browser-side CLI device approval: looking up a login code and
# submitting an approve or deny decision. Each action is counted per signed-in
# user and per source IP so one account or one network cannot enumerate codes.
module CliDeviceApprovalRateLimitGuard
  extend ActiveSupport::Concern

  WINDOW = 10.minutes
  LIMITS = {
    "lookup" => { user: 30, ip: 60 },
    "decision" => { user: 10, ip: 30 }
  }.freeze
  RATE_LIMIT_MESSAGE = "Too many CLI login code attempts. Wait a few minutes and try again."

  included do
    before_action -> { enforce_cli_device_approval_rate_limit!("lookup") }, only: :show, if: -> { params[:user_code].present? }
    before_action -> { enforce_cli_device_approval_rate_limit!("decision") }, only: :update
  end

  private

  def enforce_cli_device_approval_rate_limit!(action)
    limits = LIMITS.fetch(action)
    identities = {
      user: "user:#{current_user.id}",
      ip: "ip:#{request.remote_ip.presence || 'unknown'}"
    }
    counter = Logister::RateLimitCounter.new

    # Count every identity before deciding so both counters keep advancing.
    exceeded = identities.map do |scope, identity|
      key = [ "logister", "cli_device_approval_rate_limit", "v1", action, scope, Digest::SHA256.hexdigest(identity) ].join(":")
      # A nil count means no store could count the attempt, so fail closed.
      count = counter.increment(key, expires_in: WINDOW, kind: "cli_device_approval_#{action}")
      count.nil? || count > limits.fetch(scope)
    end
    return unless exceeded.any?

    render_cli_device_approval_rate_limited
  end

  def render_cli_device_approval_rate_limited
    response.set_header("Retry-After", WINDOW.to_i.to_s)
    @user_code = ""
    @authorization = nil
    @projects = []
    flash.now[:alert] = RATE_LIMIT_MESSAGE
    render :show, status: :too_many_requests
  end
end
