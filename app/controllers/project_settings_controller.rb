class ProjectSettingsController < ApplicationController
  include ProjectScope
  include ProjectSettingsContext

  SETTINGS_SECTIONS = ProjectSettingsNavigation::SECTIONS

  before_action :authenticate_user!
  before_action :set_settings_project

  def show
    if legacy_archive_search_path?
      redirect_to archives_project_path(@project, legacy_archive_search_params)
      return
    end

    @settings_sections = settings_sections_for_current_user
    @settings_section = normalized_settings_section
    load_project_settings_context
    render "projects/settings"
  end

  private

  def legacy_archive_search_path?
    @project.managed_by?(current_user) &&
      params[:section] == "data" &&
      params[:archive_path].in?(%w[search_archives investigations])
  end

  def legacy_archive_search_params
    raw_search = params[:archive_search]
    return {} unless raw_search.respond_to?(:permit)

    {
      archive_search: raw_search.permit(*ProjectArchiveInvestigationSearch::SEARCH_FIELDS).to_h
    }
  end

  def set_settings_project
    @project = if admin_user?
      Project.find_by!(uuid: project_uuid_param)
    else
      current_user.accessible_projects.find_by!(uuid: project_uuid_param)
    end
  end

  def settings_sections_for_current_user
    settings_navigation.sections
  end

  def normalized_settings_section
    settings_navigation.selected_section
  end

  def settings_navigation
    @settings_navigation ||= ProjectSettingsNavigation.new(
      project: @project,
      user: current_user,
      app_admin: admin_user?,
      requested_section: params[:section]
    )
  end
end
