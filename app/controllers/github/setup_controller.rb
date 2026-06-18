# frozen_string_literal: true

module Github
  class SetupController < ApplicationController
    before_action :authenticate_user!

    def show
      return redirect_to(projects_path, alert: "Missing GitHub installation id.") if params[:installation_id].blank?

      result = InstallationSync.from_setup(installation_id: params[:installation_id], installed_by: current_user)
      redirect_to setup_redirect_path,
                  notice: "GitHub App connected. Synced #{result.repositories.size} repositories."
    rescue InstallationSync::Error, AppClient::Error, AppJwt::NotConfigured,
           InstallationRepositoriesClient::Error, InstallationToken::Error => error
      Rails.logger.warn("GitHub setup failed: #{error.class} #{error.message}")
      redirect_to projects_path, alert: "GitHub App setup could not be completed."
    end

    private

    def setup_redirect_path
      project = current_user.projects.find_by(uuid: params[:state].to_s)
      return projects_path unless project

      settings_project_path(project, anchor: "source-repositories")
    end
  end
end
