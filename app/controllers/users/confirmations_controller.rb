class Users::ConfirmationsController < Devise::ConfirmationsController
  include DeviseTurnstileGuard

  prepend_before_action :validate_cloudflare_turnstile, only: :create
  rescue_from RailsCloudflareTurnstile::Forbidden, with: :turnstile_failed

  private

  def turnstile_failed
    turnstile_failed_redirect(new_user_confirmation_path)
  end
end
