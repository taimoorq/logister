require "digest"

module DeviseRateLimitGuard
  extend ActiveSupport::Concern

  RATE_LIMIT_MESSAGE = "Too many attempts. Please wait a few minutes and try again."

  RAILS_CACHE_STORE = Class.new do
    def increment(cache_key, amount = 1, expires_in:)
      count = Rails.cache.increment(cache_key, amount, expires_in: expires_in)
      return count if count

      Rails.cache.write(cache_key, amount, expires_in: expires_in)
      amount
    rescue StandardError => error
      Rails.logger.warn("Devise rate limiting skipped: #{error.class} #{error.message}")
      nil
    end
  end.new

  class_methods do
    def rate_limit_devise_create(to:, within:, by:, name:)
      prepend_before_action only: :create do
        enforce_devise_rate_limit(
          to: to,
          within: within,
          by: by,
          name: name,
          scope: "devise:#{controller_path}"
        )
      end
    end
  end

  private

  def devise_rate_limit_ip
    request.remote_ip.presence || "unknown"
  end

  def devise_rate_limit_email
    resource_params = params[resource_name]
    email = resource_params[:email] if resource_params.is_a?(ActionController::Parameters) || resource_params.is_a?(Hash)
    email = email.to_s.strip.downcase
    return "blank" if email.blank?

    Digest::SHA256.hexdigest(email)
  end

  def enforce_devise_rate_limit(to:, within:, by:, name:, scope:)
    identity = by.is_a?(Symbol) ? send(by) : instance_exec(&by)
    cache_key = devise_rate_limit_cache_key(scope, name, identity)
    count = DeviseRateLimitGuard::RAILS_CACHE_STORE.increment(cache_key, 1, expires_in: within)
    return unless count && count > to

    ActiveSupport::Notifications.instrument(
      "rate_limit.action_controller",
      request: request,
      count: count,
      to: to,
      within: within,
      by: identity,
      name: name,
      scope: scope,
      cache_key: cache_key
    ) do
      render_devise_rate_limited(retry_after: within)
    end
  end

  def devise_rate_limit_cache_key(scope, name, identity)
    [ "logister", "devise_rate_limit", "v1", scope, name, identity ].compact.join(":")
  end

  def render_devise_rate_limited(retry_after:)
    response.set_header("Retry-After", retry_after.to_i.to_s)
    render plain: DeviseRateLimitGuard::RATE_LIMIT_MESSAGE, status: :too_many_requests
  end
end
