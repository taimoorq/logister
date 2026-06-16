class Users::PasswordsController < Devise::PasswordsController
  include DeviseRateLimitGuard
  include DeviseTurnstileGuard
  layout "auth"

  prepend_before_action :validate_cloudflare_turnstile, only: :create
  rate_limit_devise_create to: 5, within: 10.minutes, by: :devise_rate_limit_ip, name: "ip"
  rate_limit_devise_create to: 3, within: 10.minutes, by: :devise_rate_limit_email, name: "email"
  rescue_from RailsCloudflareTurnstile::Forbidden, with: :turnstile_failed

  private

  def turnstile_failed
    turnstile_failed_redirect(new_user_password_path)
  end
end
