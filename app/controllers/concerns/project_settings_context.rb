module ProjectSettingsContext
  extend ActiveSupport::Concern

  private

  def load_project_settings_context
    @owner = @project.user
    @project_memberships = @project.project_memberships
                                  .select(:id, :uuid, :project_id, :user_id, :role, :created_at)
                                  .includes(:user)
                                  .order(created_at: :asc)
    @api_keys = @project.api_keys
                        .select(:id, :uuid, :project_id, :name, :last_used_at, :revoked_at, :created_at)
                        .order(created_at: :desc)
    @notification_preference ||= ProjectNotificationPreference.for(user: current_user, project: @project)
    @assignment_summary = ProjectAssignmentSummary.new(@project)
    @retention_policy ||= ProjectRetentionPolicy.for(project: @project) if @project.owned_by?(current_user)
    @public_api_rate_limit_defaults = {
      requests: Project.default_public_api_rate_limit_requests,
      period_seconds: Project.default_public_api_rate_limit_period_seconds,
      auth_failure_requests: Project.default_public_api_auth_failure_rate_limit_requests
    }
    @recent_telemetry_archives = @project.telemetry_archives
                                         .select(:id, :project_id, :scope, :before_at, :rows, :status, :created_at)
                                         .recent_first
                                         .limit(5)
  end
end
