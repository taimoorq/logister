class NotificationsController < ApplicationController
  before_action :authenticate_user!

  def dismiss
    notification_key = params.require(:notification_key).to_s
    raise ActionController::BadRequest, "Invalid notification key" unless valid_notification_key?(notification_key)

    dismissal = current_user.user_notification_dismissals.find_or_initialize_by(notification_key:)
    dismissal.dismissed_at ||= Time.current
    dismissal.save!

    redirect_back fallback_location: dashboard_path, status: :see_other
  end

  private

  def valid_notification_key?(notification_key)
    notification_key.length <= 200 && notification_key.match?(/\A[A-Za-z0-9:._-]+\z/)
  end
end
