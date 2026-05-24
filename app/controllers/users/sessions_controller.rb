class Users::SessionsController < Devise::SessionsController
  include DeviseTurnstileGuard
  layout "auth"

  prepend_before_action :validate_cloudflare_turnstile, only: :create
  rescue_from RailsCloudflareTurnstile::Forbidden, with: :turnstile_failed

  private

  def turnstile_failed
    turnstile_failed_redirect(new_user_session_path)
  end
end
