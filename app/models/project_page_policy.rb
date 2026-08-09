# frozen_string_literal: true

class ProjectPagePolicy
  attr_reader :project, :viewer, :app_admin

  def initialize(project:, viewer:, app_admin: false)
    @project = project
    @viewer = viewer
    @app_admin = app_admin
  end

  def resolve(pages)
    return pages unless settings_only?

    pages.select { |page| page.key == :settings }.freeze
  end

  private

  def settings_only?
    app_admin && !project_accessible_to_viewer?
  end

  def project_accessible_to_viewer?
    return false unless viewer
    return true if project.owned_by?(viewer)

    memberships = project.project_memberships
    if memberships.loaded?
      memberships.any? { |membership| membership.user_id == viewer.id }
    else
      memberships.exists?(user_id: viewer.id)
    end
  end
end
