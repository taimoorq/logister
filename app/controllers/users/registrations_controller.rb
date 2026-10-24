class Users::RegistrationsController < Devise::RegistrationsController
  include DeviseRateLimitGuard
  include DeviseTurnstileGuard
  layout :registration_layout

  prepend_before_action :validate_cloudflare_turnstile, only: :create
  rate_limit_devise_create to: 5, within: 1.minute, by: :devise_rate_limit_ip, name: "ip-short"
  rate_limit_devise_create to: 20, within: 1.hour, by: :devise_rate_limit_ip, name: "ip-hour"
  rate_limit_devise_create to: 3, within: 1.hour, by: :devise_rate_limit_email, name: "email-hour"

  before_action :configure_permitted_parameters
  before_action :redirect_to_instance_setup, only: [ :new, :create ]
  before_action :enforce_registration_policy, only: [ :new, :create ]
  rescue_from RailsCloudflareTurnstile::Forbidden, with: :turnstile_failed

  REGISTRATION_CLOSED_MESSAGE = "Account sign-up is not available on this instance. Ask an administrator for access."
  DOMAIN_NOT_ALLOWED_MESSAGE = "is not on a domain that can sign up on this instance"

  private

  def redirect_to_instance_setup
    return unless Installation.first_admin_setup_available?

    redirect_to instance_setup_path, notice: "Create the first administrator to continue this self-hosted installation."
  end

  # Runs after redirect_to_instance_setup, so first-administrator setup keeps
  # working whatever the sign-up mode is.
  def enforce_registration_policy
    policy = RegistrationPolicy.current
    unless policy.sign_up_available?
      redirect_to new_user_session_path, alert: REGISTRATION_CLOSED_MESSAGE
      return
    end
    return unless action_name == "create"
    return if policy.permits_email?(sign_up_params[:email])

    build_resource(sign_up_params)
    resource.errors.add(:email, DOMAIN_NOT_ALLOWED_MESSAGE)
    clean_up_passwords(resource)
    set_minimum_password_length
    render :new, status: :unprocessable_content
  end

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
