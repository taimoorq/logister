class Users::SessionsController < Devise::SessionsController
  include DeviseRateLimitGuard
  include DeviseTurnstileGuard
  layout "auth"

  prepend_before_action :validate_cloudflare_turnstile, only: :create
  rate_limit_devise_create to: 10, within: 1.minute, by: :devise_rate_limit_ip, name: "ip-short"
  rate_limit_devise_create to: 20, within: 10.minutes, by: :devise_rate_limit_email, name: "email-long"
  rescue_from RailsCloudflareTurnstile::Forbidden, with: :turnstile_failed

  private

  def turnstile_failed
    turnstile_failed_redirect(new_user_session_path)
  end
end
