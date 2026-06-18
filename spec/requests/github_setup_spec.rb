# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GitHub setup callback", type: :request do
  describe "GET /github/setup" do
    it "syncs the installation and returns to project source settings" do
      project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:one))
      repository = create(:github_repository, github_installation: installation)
      result = Github::InstallationSync::Result.new(
        status: :synced,
        installation: installation,
        repositories: [ repository ]
      )
      allow(Github::InstallationSync).to receive(:from_setup).and_return(result)
      sign_in users(:one)

      get github_setup_path, params: { installation_id: "123", state: project.uuid }

      expect(Github::InstallationSync).to have_received(:from_setup).with(
        installation_id: "123",
        installed_by: users(:one)
      )
      expect(response).to redirect_to(settings_project_path(project, anchor: "source-repositories"))
      expect(flash[:notice]).to include("Synced 1 repositories")
    end

    it "requires an authenticated user" do
      get github_setup_path, params: { installation_id: "123" }

      expect(response).to redirect_to(new_user_session_path)
    end

    it "rejects callbacks without an installation id" do
      sign_in users(:one)

      get github_setup_path

      expect(response).to redirect_to(projects_path)
      expect(flash[:alert]).to eq("Missing GitHub installation id.")
    end
  end
end
