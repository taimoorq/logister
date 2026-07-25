# frozen_string_literal: true

require "digest"

class InstanceSetupController < ApplicationController
  include DeviseRateLimitGuard

  layout "auth"

  rate_limit_devise_create to: 5, within: 10.minutes, by: :devise_rate_limit_ip, name: "setup-ip"

  before_action :redirect_if_claimed

  def new
    @user = User.new
    @setup_token_available = setup_token.present?
  end

  def create
    @user = User.new(user_params)
    @setup_token_available = setup_token.present?

    unless valid_setup_token?(params[:setup_token])
      @user.errors.add(:base, "The one-time setup token is invalid.")
      render :new, status: :unprocessable_content
      return
    end

    installation = Installation.current
    User.transaction do
      installation.lock!
      raise ActiveRecord::RecordInvalid, installation if installation.claimed?

      @user.application_admin = true
      @user.skip_confirmation!
      @user.save!
      installation.update!(
        claimed_by_user: @user,
        claimed_at: Time.current,
        onboarding_required: true
      )
    end

    sign_in(@user)
    redirect_to admin_installation_section_path("general"), notice: "Administrator account created. Start with the canonical instance settings."
  rescue ActiveRecord::RecordInvalid
    @setup_token_available = setup_token.present?
    render :new, status: :unprocessable_content
  end

  private

  def redirect_if_claimed
    return unless Installation.current_if_available&.claimed?

    redirect_to new_user_session_path, notice: "This instance already has an administrator. Sign in to manage installation settings."
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  def setup_token
    ENV["LOGISTER_SETUP_TOKEN"].to_s
  end

  def valid_setup_token?(candidate)
    return false if setup_token.blank? || candidate.to_s.blank?

    expected = Digest::SHA256.hexdigest(setup_token)
    actual = Digest::SHA256.hexdigest(candidate.to_s)
    ActiveSupport::SecurityUtils.secure_compare(expected, actual)
  end
end
