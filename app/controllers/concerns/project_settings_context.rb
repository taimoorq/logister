module ProjectSettingsContext
  extend ActiveSupport::Concern

  private

  def load_project_settings_context
    ensure_project_settings_navigation
    @owner = @project.user
    @project_memberships = @project.project_memberships
                                  .select(:id, :uuid, :project_id, :user_id, :role, :created_at)
                                  .includes(:user)
                                  .order(created_at: :asc)
    @api_keys = @project.api_keys
                        .select(:id, :uuid, :project_id, :name, :last_used_at, :revoked_at, :created_at)
                        .order(created_at: :desc)
    @notification_preference ||= ProjectNotificationPreference.for(user: current_user, project: @project)
    @cloudflare_integration_setting ||= ProjectIntegrationSetting.for(
      project: @project,
      provider: ProjectIntegrationSetting::PROVIDERS[:cloudflare_pages]
    ) if @project.integration_cloudflare_pages?
    @source_repositories = @project.source_repositories
                                   .includes(:github_installation, github_repository: :github_installation)
                                   .order(:provider, :full_name)
    @source_repository_form ||= @project.source_repositories.new(
      provider: ProjectSourceRepository::PROVIDERS[:github],
      enabled: true
    )
    @github_app_configured = Logister::GithubAppConfig.configured?
    @project_manager = @project.managed_by?(current_user)
    @github_app_install_url = Logister::GithubAppConfig.install_url(state: @project.uuid) if @project_manager
    @github_setup_url = github_setup_url
    @github_webhook_url = github_webhooks_url
    @github_app_diagnostics = Github::ConfigurationDiagnostics.call(
      setup_url: @github_setup_url,
      webhook_url: @github_webhook_url,
      install_url: @github_app_install_url
    )
    @github_integration_state = ProjectGithubIntegrationState.new(
      project: @project,
      user: current_user,
      source_repositories: @source_repositories,
      app_diagnostics: @github_app_diagnostics
    )
    @project_github_installations = @github_integration_state.project_installations
    @linked_github_installations = @github_integration_state.linked_installations
    @linkable_github_installations = @github_integration_state.linkable_installations
    @available_github_repositories = @github_integration_state.available_repositories
    @connectable_github_repositories = @github_integration_state.connectable_repositories
    @assignment_summary = ProjectAssignmentSummary.new(@project)
    @retention_policy ||= ProjectRetentionPolicy.for(project: @project) if @project_manager
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

  def ensure_project_settings_navigation
    return unless defined?(ProjectSettingsController::SETTINGS_SECTIONS)

    navigation = ProjectSettingsNavigation.new(
      project: @project,
      user: current_user,
      app_admin: respond_to?(:admin_user?, true) && admin_user?,
      requested_section: @settings_section.presence || params[:section]
    )
    @settings_sections ||= navigation.sections
    @settings_section = navigation.selected_section
  end
end
