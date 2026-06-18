class ProjectSettingsController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  SETTINGS_SECTIONS = {
    "general" => "General",
    "notifications" => "Notifications",
    "team" => "Team",
    "integrations" => "Integrations",
    "data" => "Data",
    "danger" => "Danger",
    "admin" => "Admin"
  }.freeze

  before_action :authenticate_user!
  before_action :set_settings_project

  def show
    @settings_sections = settings_sections_for_current_user
    @settings_section = normalized_settings_section
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

  def settings_sections_for_current_user
    sections = %w[general notifications]
    sections += %w[team integrations data danger] if @project.owned_by?(current_user)
    sections << "admin" if admin_user?

    SETTINGS_SECTIONS.slice(*sections)
  end

  def normalized_settings_section
    requested = params[:section].to_s
    return requested if @settings_sections.key?(requested)

    "general"
  end
end
