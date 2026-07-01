# frozen_string_literal: true

class CliDeviceAuthorizationsController < ApplicationController
  before_action :authenticate_user!

  def show
    load_authorization_context
  end

  def update
    @authorization = CliDeviceAuthorization.find_by_user_code(params[:user_code])

    unless approvable_authorization?(@authorization)
      redirect_to cli_device_authorization_path, alert: "That CLI login code is invalid or expired."
      return
    end

    if params[:decision] == "deny"
      @authorization.deny!
      redirect_to cli_device_authorization_path(user_code: @authorization.user_code_display), notice: "CLI login request denied."
      return
    end

    @authorization.approve!(
      user: current_user,
      all_projects: params[:all_projects],
      allowed_project_ids: params[:project_ids]
    )
    redirect_to cli_device_authorization_path(user_code: @authorization.user_code_display), notice: "CLI login approved. Return to your terminal."
  rescue ActiveRecord::RecordInvalid => e
    load_authorization_context
    flash.now[:alert] = e.record.errors.full_messages.to_sentence.presence || "CLI login could not be approved."
    render :show, status: :unprocessable_content
  end

  private

  def load_authorization_context
    @user_code = params[:user_code].to_s.strip
    @authorization = @user_code.present? ? CliDeviceAuthorization.find_by_user_code(@user_code) : nil
    @projects = current_user.active_projects.order(:name, :id).to_a
  end

  def approvable_authorization?(authorization)
    authorization&.pending? && !authorization.expired?
  end
end
