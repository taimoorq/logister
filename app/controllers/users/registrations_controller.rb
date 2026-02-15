class Users::RegistrationsController < Devise::RegistrationsController
  include DeviseTurnstileGuard

  prepend_before_action :validate_cloudflare_turnstile, only: :create
  rescue_from RailsCloudflareTurnstile::Forbidden, with: :turnstile_failed

  private

  def turnstile_failed
    turnstile_failed_redirect(new_user_registration_path)
  end
end
