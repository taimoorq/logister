# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GitHub installations", type: :request do
  describe "POST /projects/:project_uuid/github/installations/:uuid/sync" do
    it "resyncs repositories for an installation owned by the current user" do
      project = create(:project, user: users(:one), slug: "newsfeedreader", name: "News Feed Reader")
      installation = create(:github_installation, installed_by: users(:one))
      create(:project_github_installation, project: project, github_installation: installation, linked_by: users(:one))
      create(:github_repository, github_installation: installation, full_name: "taimoorq/logister")
      create(:github_repository, github_installation: installation, full_name: "taimoorq/newsfeedreader")
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
      expect(project.source_repositories).to be_empty
    end

    it "allows a project admin to sync a linked installation they did not install" do
      project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:two))
      create(:project_membership, project: project, user: users(:two), role: :admin)
      create(:project_github_installation, project: project, github_installation: installation, linked_by: users(:one))
      result = Github::InstallationSync::Result.new(status: :synced, installation: installation, repositories: [])
      allow(Github::InstallationSync).to receive(:resync).and_return(result)
      sign_in users(:two)

      post project_github_installation_sync_path(project, installation)

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
      expect(Github::InstallationSync).to have_received(:resync).with(installation: installation)
    end

    it "does not allow syncing an installation unlinked from the project" do
      project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:one))
      allow(Github::InstallationSync).to receive(:resync)
      sign_in users(:one)

      post project_github_installation_sync_path(project, installation)

      expect(response).to have_http_status(:not_found)
      expect(Github::InstallationSync).not_to have_received(:resync)
    end

    it "redirects with an alert when GitHub sync fails" do
      project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:one))
      create(:project_github_installation, project: project, github_installation: installation, linked_by: users(:one))
      allow(Github::InstallationSync).to receive(:resync).and_raise(Github::InstallationSync::Error, "unavailable")
      sign_in users(:one)

      post project_github_installation_sync_path(project, installation)

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
      expect(flash[:alert]).to eq("GitHub repositories could not be synced.")
    end
  end

  describe "POST /projects/:project_uuid/github_installation_links" do
    it "links an existing installation installed by the current user" do
      project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:one))
      sign_in users(:one)

      expect {
        post project_github_installation_links_path(project), params: {
          github_installation: { uuid: installation.uuid }
        }
      }.to change(ProjectGithubInstallation, :count).by(1)

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
      expect(project.github_installations.reload).to include(installation)
    end

    it "allows one installation to be linked to multiple projects" do
      first_project = create(:project, user: users(:one))
      second_project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:one))
      sign_in users(:one)

      post project_github_installation_links_path(first_project), params: {
        github_installation: { uuid: installation.uuid }
      }
      post project_github_installation_links_path(second_project), params: {
        github_installation: { uuid: installation.uuid }
      }

      expect(installation.projects.reload).to contain_exactly(first_project, second_project)
    end

    it "allows project admins to link their own existing installation" do
      project = create(:project, user: users(:one))
      create(:project_membership, project: project, user: users(:two), role: :admin)
      installation = create(:github_installation, installed_by: users(:two))
      sign_in users(:two)

      post project_github_installation_links_path(project), params: {
        github_installation: { uuid: installation.uuid }
      }

      expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "source-repositories"))
      expect(project.github_installations.reload).to include(installation)
    end

    it "does not allow viewers to link installations" do
      project = create(:project, user: users(:one))
      create(:project_membership, project: project, user: users(:two), role: :viewer)
      installation = create(:github_installation, installed_by: users(:two))
      sign_in users(:two)

      post project_github_installation_links_path(project), params: {
        github_installation: { uuid: installation.uuid }
      }

      expect(response).to have_http_status(:not_found)
      expect(project.github_installations.reload).to be_empty
    end
  end
end
