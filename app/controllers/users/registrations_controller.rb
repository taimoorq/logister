class Users::RegistrationsController < Devise::RegistrationsController
  include DeviseTurnstileGuard

  before_action :configure_permitted_parameters
  prepend_before_action :validate_cloudflare_turnstile, only: :create
  rescue_from RailsCloudflareTurnstile::Forbidden, with: :turnstile_failed

  private

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name ])
  end

  def turnstile_failed
    turnstile_failed_redirect(new_user_registration_path)
  end
end
