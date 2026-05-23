module ProjectSettingsContext
  extend ActiveSupport::Concern

  private

  def load_project_settings_context
    @owner = @project.user
    @project_memberships = @project.project_memberships.includes(:user).order(created_at: :asc)
    @api_keys = @project.api_keys.order(created_at: :desc)
    @notification_preference ||= ProjectNotificationPreference.for(user: current_user, project: @project)
    @assignment_summary = ProjectAssignmentSummary.new(@project)
    @retention_policy ||= ProjectRetentionPolicy.for(project: @project) if @project.owned_by?(current_user)
    @recent_telemetry_archives = @project.telemetry_archives.recent_first.limit(5)
  end
end
