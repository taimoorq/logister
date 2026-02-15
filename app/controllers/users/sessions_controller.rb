class Users::SessionsController < Devise::SessionsController
  prepend_before_action :validate_cloudflare_turnstile, only: :create
  rescue_from RailsCloudflareTurnstile::Forbidden, with: :turnstile_failed

  private

  def turnstile_failed
    flash[:alert] = "Please complete the verification challenge and try again."
    redirect_to new_user_session_path
  end
end
