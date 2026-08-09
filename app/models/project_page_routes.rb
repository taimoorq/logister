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
    settings: :settings_project_path,
    edit: :edit_project_path,
    setup: :setup_project_path
  }.freeze

  class << self
    def path_for(route_key, project)
      Rails.application.routes.url_helpers.public_send(ROUTE_METHODS.fetch(route_key.to_sym), project)
    end

    def validate!(route_key)
      ROUTE_METHODS.fetch(route_key.to_sym)
      true
    end
  end
end
