# frozen_string_literal: true

require "rails_helper"
require "cgi"

RSpec.describe "Project source repositories", type: :request do
  describe "POST /projects/:uuid/source_repositories" do
    it "adds a source repository to an owned project" do
      project = create(:project, user: users(:one))
      sign_in users(:one)

      post project_source_repositories_path(project), params: {
        project_source_repository: {
          provider: "github",
          full_name: " https://github.com/acme/storefront.git ",
          default_branch: " main ",
          runtime_root: " /app ",
          source_root: " services/storefront ",
          enabled: "1"
        }
      }

      expect(response).to redirect_to(settings_project_path(project, anchor: "source-repositories"))
      repository = project.source_repositories.find_by!(full_name: "acme/storefront")
      expect(repository).to be_enabled
      expect(repository.default_branch).to eq("main")
      expect(repository.runtime_root).to eq("/app")
      expect(repository.source_root).to eq("services/storefront")
    end

    it "renders settings with validation errors" do
      project = create(:project, user: users(:one))
      sign_in users(:one)

      post project_source_repositories_path(project), params: {
        project_source_repository: {
          provider: "github",
          full_name: "not a repo",
          source_root: "../bad",
          enabled: "1"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Source repositories")
      expect(CGI.unescapeHTML(response.body)).to include("Source root cannot include path traversal")
    end

    it "adds a source repository from a synced GitHub repository" do
      project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:one))
      github_repository = create(
        :github_repository,
        github_installation: installation,
        full_name: "acme/private-api",
        default_branch: "trunk",
        external_id: 555
      )
      sign_in users(:one)

      post project_source_repositories_path(project), params: {
        project_source_repository: {
          provider: "github",
          github_repository_id: github_repository.id,
          runtime_root: "/srv/app",
          enabled: "1"
        }
      }

      expect(response).to redirect_to(settings_project_path(project, anchor: "source-repositories"))
      repository = project.source_repositories.find_by!(full_name: "acme/private-api")
      expect(repository.github_repository).to eq(github_repository)
      expect(repository.github_installation).to eq(installation)
      expect(repository.default_branch).to eq("trunk")
      expect(repository.external_id).to eq(555)
    end

    it "does not attach synced repositories from another user's installation" do
      project = create(:project, user: users(:one))
      github_repository = create(
        :github_repository,
        github_installation: create(:github_installation, installed_by: users(:two))
      )
      sign_in users(:one)

      post project_source_repositories_path(project), params: {
        project_source_repository: {
          provider: "github",
          github_repository_id: github_repository.id,
          enabled: "1"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(project.source_repositories).to be_empty
    end

    it "does not allow shared members to update source repositories" do
      project = create(:project, user: users(:one))
      create(:project_membership, project: project, user: users(:two))
      sign_in users(:two)

      post project_source_repositories_path(project), params: {
        project_source_repository: {
          provider: "github",
          full_name: "acme/storefront"
        }
      }

      expect(response).to have_http_status(:not_found)
      expect(project.source_repositories).to be_empty
    end
  end

  describe "PATCH /projects/:uuid/source_repositories/:uuid" do
    it "updates source repository mappings" do
      project = create(:project, user: users(:one))
      repository = create(:project_source_repository, project: project, full_name: "acme/storefront")
      sign_in users(:one)

      patch project_source_repository_path(project, repository), params: {
        project_source_repository: {
          provider: "github",
          full_name: "acme/storefront",
          default_branch: "production",
          runtime_root: "/srv/app",
          source_root: "apps/web",
          enabled: "0"
        }
      }

      expect(response).to redirect_to(settings_project_path(project, anchor: "source-repositories"))
      repository.reload
      expect(repository.default_branch).to eq("production")
      expect(repository.runtime_root).to eq("/srv/app")
      expect(repository.source_root).to eq("apps/web")
      expect(repository).not_to be_enabled
    end
  end

  describe "GET /projects/:uuid/settings" do
    it "shows source repository settings for project owners" do
      project = create(:project, user: users(:one))
      installation = create(:github_installation, installed_by: users(:one), account_login: "acme")
      create(:github_repository, github_installation: installation, full_name: "acme/private-api")
      sign_in users(:one)

      get settings_project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Source repositories")
      expect(response.body).to include("acme/private-api")
      expect(response.body).to include("GitHub setup callback")
      expect(response.body).to include("Webhook URL")
      expect(response.body).to include("LOGISTER_GITHUB_APP_ID")
      expect(response.body).to include("acme")
      expect(response.body).to include("Sync repositories")
    end
  end
end
