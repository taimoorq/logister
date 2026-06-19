# frozen_string_literal: true

module Github
  class InstallationsController < ApplicationController
    include ProjectScope

    before_action :authenticate_user!
    before_action :set_owned_project
    before_action :set_installation

    def sync
      result = InstallationSync.resync(installation: @installation)
      connection = ProjectSourceRepositoryAutoConnector.call(
        project: @project,
        github_repositories: result.repositories
      )

      redirect_to settings_project_path(@project, section: "integrations", anchor: "source-repositories"),
                  notice: sync_notice(result, connection)
    rescue InstallationSync::Error, InstallationRepositoriesClient::Error, InstallationToken::Error => error
      Rails.logger.warn("GitHub installation sync failed: #{error.class} #{error.message}")
      redirect_to settings_project_path(@project, section: "integrations", anchor: "source-repositories"),
                  alert: "GitHub repositories could not be synced."
    end

    private

    def set_installation
      @installation = GithubInstallation.visible_to(current_user).find_by!(uuid: params[:uuid])
    end

    def sync_notice(result, connection)
      notice = "GitHub repositories synced. Found #{result.repositories.size} repositories."
      return notice unless connection.connected?

      "#{notice} Connected #{connection.source_repository.full_name} as this project's source repository."
    end
  end
end
