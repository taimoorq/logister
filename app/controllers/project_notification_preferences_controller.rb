class ProjectNotificationPreferencesController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  skip_before_action :verify_authenticity_token, only: :unsubscribe
  before_action :authenticate_user!, only: :update
  before_action :set_accessible_project, only: :update

  def update
    @notification_preference = ProjectNotificationPreference.for(user: current_user, project: @project)
    notification_path = normalized_notification_path

    if @notification_preference.update(notification_preference_params)
      redirect_options = { section: "notifications" }
      redirect_options[:notification_path] = notification_path unless notification_path == DEFAULT_NOTIFICATION_PATH
      redirect_to settings_project_path(@project, redirect_options), notice: "Email notification settings updated."
    else
      @settings_section = "notifications"
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
      :regression_enabled,
      :frequent_error_enabled,
      :frequent_error_threshold_count,
      :frequent_error_window_minutes,
      :milestone_alerts_enabled,
      :workflow_mode,
      :monitor_alerts_enabled,
      :project_spike_enabled,
      :project_spike_threshold_count,
      :project_spike_window_minutes,
      :performance_alerts_enabled,
      :performance_p95_threshold_ms,
      :release_notifications_enabled,
      :usage_notifications_enabled,
      :retention_notifications_enabled,
      :environment_filter,
      :severity_filter,
      :status_filter,
      :immediate_email_limit_per_hour,
      :quiet_hours_enabled,
      :quiet_hours_start,
      :quiet_hours_end,
      :digest_frequency,
      :digest_send_hour,
      :time_zone
    )
  end
end
