# frozen_string_literal: true

module Github
  class InstallationsController < ApplicationController
    include ProjectScope

    before_action :authenticate_user!
    before_action :set_owned_project
    before_action :set_installation

    def sync
      result = InstallationSync.resync(installation: @installation)

      redirect_to settings_project_path(@project, anchor: "source-repositories"),
                  notice: "GitHub repositories synced. Found #{result.repositories.size} repositories."
    rescue InstallationSync::Error, InstallationRepositoriesClient::Error, InstallationToken::Error => error
      Rails.logger.warn("GitHub installation sync failed: #{error.class} #{error.message}")
      redirect_to settings_project_path(@project, anchor: "source-repositories"),
                  alert: "GitHub repositories could not be synced."
    end

    private

    def set_installation
      @installation = GithubInstallation.visible_to(current_user).find_by!(uuid: params[:uuid])
    end
  end
end
