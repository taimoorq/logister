class ProjectSettingsController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_settings_project

  def show
    load_project_settings_context
    render "projects/settings"
  end

  private

  def set_settings_project
    @project = if admin_user?
      Project.find_by!(uuid: project_uuid_param)
    else
      current_user.accessible_projects.find_by!(uuid: project_uuid_param)
    end
  end
end
