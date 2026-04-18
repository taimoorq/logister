class ProjectSettingsController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_accessible_project

  def show
    @owner = @project.user
    @project_memberships = @project.project_memberships.includes(:user).order(created_at: :asc)
    @api_keys = @project.api_keys.order(created_at: :desc)

    render "projects/settings"
  end
end
