class ProjectSetupController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    load_project_settings_context
    @setup_active_api_key_count = @api_keys.count(&:active?)
    @setup_has_events = @project.ingest_events.exists?
    @setup_has_source_repository = @source_repositories.any?(&:enabled?)
    @setup_has_deployments = @project.deployments.exists?

    render "projects/setup"
  end
end
