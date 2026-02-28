class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  private

  def require_admin!
    return if admin_user?

    redirect_to root_path, alert: "Admin access is required."
  end
end
