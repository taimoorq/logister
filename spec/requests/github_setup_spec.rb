# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GitHub setup callback", type: :request do
  describe "GET /github/setup" do
    it "syncs the installation and returns to project source settings" do
      project = create(:project, user: users(:one), slug: "newsfeedreader", name: "News Feed Reader")
      installation = create(:github_installation, installed_by: users(:one))
      create(:github_repository, github_installation: installation, full_name: "taimoorq/logister")
      create(:github_repository, github_installation: installation, full_name: "taimoorq/newsfeedreader")
      result = Github::InstallationSync::Result.new(
        status: :synced,
        installation: installation,
        repositories: installation.github_repositories.to_a
      )
      allow(Github::InstallationSync).to receive(:from_setup).and_return(result)
      sign_in users(:one)

      expect {
        get github_setup_path, params: { installation_id: "123", state: project.uuid }
      }.not_to change(ProjectSourceRepository, :count)
      expect(Github::InstallationSync).to have_received(:from_setup).with(
        installation_id: "123",
        installed_by: users(:one)
      )
      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
      expect(flash[:notice]).to include("Synced 2 repositories")
      expect(flash[:notice]).to include("Select repositories below")
      expect(project.github_installations).to include(installation)
      expect(project.source_repositories).to be_empty
    end

    it "links the installation when the setup state belongs to a project admin" do
      project = create(:project, user: users(:one))
      create(:project_membership, project: project, user: users(:two), role: :admin)
      installation = create(:github_installation, installed_by: users(:two))
      result = Github::InstallationSync::Result.new(
        status: :synced,
        installation: installation,
        repositories: []
      )
      allow(Github::InstallationSync).to receive(:from_setup).and_return(result)
      sign_in users(:two)

      get github_setup_path, params: { installation_id: "123", state: project.uuid }

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
      expect(project.github_installations).to include(installation)
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
