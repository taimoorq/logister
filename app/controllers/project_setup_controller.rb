class ProjectSetupController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    load_project_settings_context(include: :setup)
    @settings_section = "setup"
    @setup_status = ProjectSetupStatus.new(@project).call
    @setup_steps = ProjectExperience.for(@project).setup_steps(status: @setup_status, manager: @project_manager)
    @self_monitoring_status = Logister::SelfMonitoringStatus.new(project: @project)

    render "projects/setup"
  end
end
