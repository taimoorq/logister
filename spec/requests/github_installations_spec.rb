# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GitHub installations", type: :request do
  describe "POST /projects/:project_uuid/github/installations/:uuid/sync" do
    it "resyncs repositories for an installation owned by the current user" do
      project = create(:project, user: users(:one), slug: "newsfeedreader", name: "News Feed Reader")
      installation = create(:github_installation, installed_by: users(:one))
      create(:github_repository, github_installation: installation, full_name: "taimoorq/logister")
      repository = create(:github_repository, github_installation: installation, full_name: "taimoorq/newsfeedreader")
      result = Github::InstallationSync::Result.new(
        status: :synced,
        installation: installation,
        repositories: installation.github_repositories.to_a
      )
      allow(Github::InstallationSync).to receive(:resync).and_return(result)
      sign_in users(:one)

      post project_github_installation_sync_path(project, installation)

      expect(Github::InstallationSync).to have_received(:resync).with(installation: installation)
      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
      expect(flash[:notice]).to include("Found 2 repositories")
      expect(flash[:notice]).to include("Connected taimoorq/newsfeedreader")
      expect(project.source_repositories.find_by!(full_name: "taimoorq/newsfeedreader").github_repository).to eq(repository)
    end

    it "does not allow syncing another user's installation" do
      project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:two))
      allow(Github::InstallationSync).to receive(:resync)
      sign_in users(:one)

      post project_github_installation_sync_path(project, installation)

      expect(response).to have_http_status(:not_found)
      expect(Github::InstallationSync).not_to have_received(:resync)
    end

    it "redirects with an alert when GitHub sync fails" do
      project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:one))
      allow(Github::InstallationSync).to receive(:resync).and_raise(Github::InstallationSync::Error, "unavailable")
      sign_in users(:one)

      post project_github_installation_sync_path(project, installation)

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
      expect(flash[:alert]).to eq("GitHub repositories could not be synced.")
    end
  end
end
