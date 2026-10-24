class ProjectNotificationPreferencesController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext
  include SetupWizardReturn

  # RFC 8058 one-click unsubscribe: mail providers POST without a CSRF token.
  # The signed token in the URL is the credential, and GET only confirms.
  skip_before_action :verify_authenticity_token, only: :unsubscribe
  before_action :authenticate_user!, only: :update
  before_action :set_accessible_project, only: :update
  before_action :set_unsubscribe_preference, only: [ :confirm_unsubscribe, :unsubscribe ]

  def update
    @notification_preference = ProjectNotificationPreference.for(user: current_user, project: @project)
    notification_path = normalized_notification_path

    if @notification_preference.update(notification_preference_params)
      redirect_options = { section: "notifications" }
      redirect_options[:notification_path] = notification_path unless notification_path == DEFAULT_NOTIFICATION_PATH
      redirect_to (setup_return_path || settings_project_path(@project, redirect_options)), notice: "Email notification settings updated."
    else
      return if render_setup_return_with_errors(@notification_preference.errors.full_messages.to_sentence)

      @settings_section = "notifications"
      load_project_settings_context
      render "projects/settings", status: :unprocessable_content
    end
  end

  def confirm_unsubscribe
    render :confirm_unsubscribe, layout: "auth"
  end

  def unsubscribe
    @preference.unsubscribe_from_project_email!

    respond_to do |format|
      format.html { render :unsubscribed, layout: "auth" }
      format.any { head :ok }
    end
  end

  private

  def set_unsubscribe_preference
    @preference = ProjectNotificationPreference.find_by_unsubscribe_token(params[:token])
    return if @preference

    respond_to do |format|
      format.html { render :invalid_unsubscribe, layout: "auth", status: :not_found }
      format.any { head :not_found }
    end
  end

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
      :mobile_health_notifications_enabled,
      :release_notifications_enabled,
      :usage_notifications_enabled,
      :retention_notifications_enabled,
      :environment_filter,
      :severity_filter,
      :status_filter,
      :mobile_source_filter,
      :mobile_diagnostic_kind_filter,
      :mobile_build_filter,
      :mobile_channel_filter,
      :mobile_artifact_state_filter,
      :late_arrival_policy,
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
