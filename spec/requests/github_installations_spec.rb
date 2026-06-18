# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GitHub installations", type: :request do
  describe "POST /projects/:project_uuid/github/installations/:uuid/sync" do
    it "resyncs repositories for an installation owned by the current user" do
      project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:one))
      repository = create(:github_repository, github_installation: installation)
      result = Github::InstallationSync::Result.new(
        status: :synced,
        installation: installation,
        repositories: [ repository ]
      )
      allow(Github::InstallationSync).to receive(:resync).and_return(result)
      sign_in users(:one)

      post project_github_installation_sync_path(project, installation)

      expect(Github::InstallationSync).to have_received(:resync).with(installation: installation)
      expect(response).to redirect_to(settings_project_path(project, anchor: "source-repositories"))
      expect(flash[:notice]).to include("Found 1 repositories")
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

      expect(response).to redirect_to(settings_project_path(project, anchor: "source-repositories"))
      expect(flash[:alert]).to eq("GitHub repositories could not be synced.")
    end
  end
end
