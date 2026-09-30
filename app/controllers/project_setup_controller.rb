class ProjectSetupController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    load_project_settings_context(include: :setup)
    @settings_section = "setup"
    ProjectSetupSummary.expire(@project)
    @setup_plan = ProjectSetupPlan.for(@project, viewer: current_user)
    @self_monitoring_status = Logister::SelfMonitoringStatus.new(project: @project)

    render "projects/setup"
  end
end
