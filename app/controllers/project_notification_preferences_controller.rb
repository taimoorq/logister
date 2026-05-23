class ProjectNotificationPreferencesController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  skip_before_action :verify_authenticity_token, only: :unsubscribe
  before_action :authenticate_user!, only: :update
  before_action :set_accessible_project, only: :update

  def update
    @notification_preference = ProjectNotificationPreference.for(user: current_user, project: @project)

    if @notification_preference.update(notification_preference_params)
      redirect_to settings_project_path(@project, anchor: "notifications"), notice: "Email notification settings updated."
    else
      load_project_settings_context
      render "projects/settings", status: :unprocessable_content
    end
  end

  def unsubscribe
    preference = ProjectNotificationPreference.find_signed!(params[:token], purpose: :notification_unsubscribe)
    preference.unsubscribe_from_project_email!

    respond_to do |format|
      format.html { render plain: "You have been unsubscribed from Logister email notifications for this project." }
      format.any { head :ok }
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { render plain: "This unsubscribe link is no longer valid.", status: :not_found }
      format.any { head :not_found }
    end
  end

  private

  def notification_preference_params
    params.require(:project_notification_preference).permit(
      :first_occurrence_enabled,
      :digest_frequency,
      :digest_send_hour,
      :time_zone
    )
  end
end
