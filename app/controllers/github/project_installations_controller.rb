# frozen_string_literal: true

module Github
  class ProjectInstallationsController < ApplicationController
    include ProjectScope

    before_action :authenticate_user!
    before_action :set_managed_project

    def create
      installation = GithubInstallation.linkable_by(current_user).find_by!(uuid: installation_uuid_param)
      @project.project_github_installations.find_or_create_by!(github_installation: installation) do |link|
        link.linked_by = current_user
      end

      redirect_to settings_project_path(@project, section: "integrations", anchor: "source-repositories"),
                  notice: "#{installation.account_login} GitHub App installation linked to this project."
    end

    def destroy
      link = @project.project_github_installations.includes(:github_installation).find_by!(uuid: params[:uuid])
      installation = link.github_installation

      if @project.source_repositories.where(github_installation: installation).or(
        @project.source_repositories.where(github_repository_id: installation.github_repositories.select(:id))
      ).exists?
        redirect_to settings_project_path(@project, section: "integrations", anchor: "source-repositories"),
                    alert: "Remove connected source repositories before unlinking #{installation.account_login}."
        return
      end

      link.destroy!
      redirect_to settings_project_path(@project, section: "integrations", anchor: "source-repositories"),
                  notice: "#{installation.account_login} GitHub App installation unlinked from this project."
    end

    private

    def installation_uuid_param
      params.require(:github_installation).fetch(:uuid)
    end
  end
end
