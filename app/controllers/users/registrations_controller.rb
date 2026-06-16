class Users::RegistrationsController < Devise::RegistrationsController
  include DeviseRateLimitGuard
  include DeviseTurnstileGuard
  layout :registration_layout

  prepend_before_action :validate_cloudflare_turnstile, only: :create
  rate_limit_devise_create to: 5, within: 1.minute, by: :devise_rate_limit_ip, name: "ip-short"
  rate_limit_devise_create to: 20, within: 1.hour, by: :devise_rate_limit_ip, name: "ip-hour"
  rate_limit_devise_create to: 3, within: 1.hour, by: :devise_rate_limit_email, name: "email-hour"

  before_action :configure_permitted_parameters
  rescue_from RailsCloudflareTurnstile::Forbidden, with: :turnstile_failed

  private

  def registration_layout
    %w[new create].include?(action_name) ? "auth" : "application"
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name ])
  end

  def turnstile_failed
    turnstile_failed_redirect(new_user_registration_path)
  end
end
