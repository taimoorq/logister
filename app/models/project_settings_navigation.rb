# frozen_string_literal: true

class ProjectSettingsNavigation
  SECTIONS = {
    "general" => "General",
    "notifications" => "Notifications",
    "team" => "Team",
    "integrations" => "Integrations",
    "data" => "Data",
    "danger" => "Danger",
    "admin" => "Admin"
  }.freeze

  def initialize(project:, user:, app_admin: false, requested_section: nil)
    @project = project
    @user = user
    @app_admin = app_admin
    @requested_section = requested_section.to_s
  end

  def sections
    SECTIONS.slice(*section_keys)
  end

  def selected_section
    return requested_section if sections.key?(requested_section)

    "general"
  end

  private

  attr_reader :project, :user, :requested_section

  def section_keys
    keys = %w[general notifications]
    keys += %w[team integrations data] if project.managed_by?(user)
    keys << "danger" if project.owned_by?(user)
    keys << "admin" if app_admin?
    keys
  end

  def app_admin?
    @app_admin
  end
end
