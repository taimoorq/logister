# frozen_string_literal: true

class ProjectPageRoutes
  ROUTE_METHODS = {
    overview: :project_path,
    inbox: :inbox_project_path,
    activity: :activity_project_path,
    insights: :insights_project_path,
    performance: :performance_project_path,
    releases: :releases_project_path,
    artifacts: :artifacts_project_path,
    monitors: :monitors_project_path,
    deployments: :deployments_project_path,
    archives: :archives_project_path,
    connections: :connections_project_path,
    project_links: :project_project_links_path,
    settings: :settings_project_path,
    setup: :setup_project_path
  }.freeze

  class << self
    def path_for(route_key, project)
      Rails.application.routes.url_helpers.public_send(ROUTE_METHODS.fetch(route_key.to_sym), project)
    end

    # Where a section opens for a project: the section's first navigable view, or
    # its only page. It reads the static catalog, so it costs no queries and works
    # for any project, which is what lets the project menu keep your section.
    def section_path(project, section_key)
      pages = ProjectExperience.definition_for(project.integration_kind).pages
                               .select { |page| page.section_key == section_key.to_sym && !page.hidden? }
                               .sort_by(&:order)
      page = pages.find(&:view?) || pages.first
      path_for(page ? page.route_key : :overview, project)
    end

    def validate!(route_key)
      ROUTE_METHODS.fetch(route_key.to_sym)
      true
    end
  end
end
