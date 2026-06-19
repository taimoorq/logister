# frozen_string_literal: true

module Github
  class SetupController < ApplicationController
    before_action :authenticate_user!

    def show
      return redirect_to(projects_path, alert: "Missing GitHub installation id.") if params[:installation_id].blank?

      result = InstallationSync.from_setup(installation_id: params[:installation_id], installed_by: current_user)
      project = setup_project
      connection = auto_connect_source_repository(project, result.repositories)

      redirect_to setup_redirect_path(project),
                  notice: setup_notice(result, connection)
    rescue InstallationSync::Error, AppClient::Error, AppJwt::NotConfigured,
           InstallationRepositoriesClient::Error, InstallationToken::Error => error
      Rails.logger.warn("GitHub setup failed: #{error.class} #{error.message}")
      redirect_to projects_path, alert: "GitHub App setup could not be completed."
    end

    private

    def setup_project
      @setup_project ||= current_user.projects.find_by(uuid: params[:state].to_s)
    end

    def setup_redirect_path(project)
      return projects_path unless project

      settings_project_path(project, section: "integrations", anchor: "source-repositories")
    end

    def auto_connect_source_repository(project, repositories)
      return unless project

      ProjectSourceRepositoryAutoConnector.call(project: project, github_repositories: repositories)
    end

    def setup_notice(result, connection)
      notice = "GitHub App connected. Synced #{result.repositories.size} repositories."
      return notice unless connection&.connected?

      "#{notice} Connected #{connection.source_repository.full_name} as this project's source repository."
    end
  end
end
