# frozen_string_literal: true

module Github
  class SetupController < ApplicationController
    before_action :authenticate_user!

    def show
      return redirect_to(projects_path, alert: "Missing GitHub installation id.") if params[:installation_id].blank?

      result = InstallationSync.from_setup(installation_id: params[:installation_id], installed_by: current_user)
      project = setup_project
      link_installation_to_project(project, result.installation) if project

      redirect_to setup_redirect_path(project),
                  notice: setup_notice(result, project)
    rescue InstallationSync::Error, AppClient::Error, AppJwt::NotConfigured,
           InstallationRepositoriesClient::Error, InstallationToken::Error => error
      Rails.logger.warn("GitHub setup failed: #{error.class} #{error.message}")
      redirect_to projects_path, alert: "GitHub App setup could not be completed."
    end

    private

    def setup_project
      @setup_project ||= current_user.manageable_projects.find_by(uuid: params[:state].to_s)
    end

    def setup_redirect_path(project)
      return projects_path unless project

      settings_project_path(project, section: "integrations", anchor: "source-repositories")
    end

    def link_installation_to_project(project, installation)
      project.project_github_installations.find_or_create_by!(github_installation: installation) do |link|
        link.linked_by = current_user
      end
    end

    def setup_notice(result, project)
      notice = "GitHub App connected. Synced #{result.repositories.size} repositories."
      return notice unless project

      "#{notice} Select repositories below to connect them to this project."
    end
  end
end
