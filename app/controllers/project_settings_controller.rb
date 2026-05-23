class ProjectSettingsController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    load_project_settings_context
    render "projects/settings"
  end
end
