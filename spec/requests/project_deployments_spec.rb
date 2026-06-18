# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project deployments", type: :request do
  before { sign_in users(:one) }

  it "lists recorded deployments with GitHub metadata" do
    project = create(:project, user: users(:one), name: "Deploy App")
    repository = create(:project_source_repository, project: project, full_name: "acme/storefront")
    create(
      :project_deployment,
      project: project,
      project_source_repository: repository,
      repository_full_name: "acme/storefront",
      release: "2026.06.17",
      commit_sha: "abc1234",
      deployed_at: 1.day.ago
    )
    create(
      :project_deployment,
      project: project,
      project_source_repository: repository,
      repository_full_name: "acme/storefront",
      release: "2026.06.18",
      commit_sha: "def5678",
      branch: "main",
      metadata: {
        "pull_request_number" => "42",
        "release_tag" => "v2026.06.18"
      }
    )

    get deployments_project_path(project)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Deployments")
    expect(response.body).to include("2026.06.18")
    expect(response.body).to include("acme/storefront")
    expect(response.body).to include("def5678")
    expect(response.body).to include("PR #42")
    expect(response.body).to include("https://github.com/acme/storefront/releases/tag/v2026.06.18")
    expect(response.body).to include("https://github.com/acme/storefront/compare/abc1234...def5678")
  end

  it "filters deployments by repository and search term" do
    project = create(:project, user: users(:one))
    storefront = create(:project_source_repository, project: project, full_name: "acme/storefront")
    api = create(:project_source_repository, project: project, full_name: "acme/api")
    create(:project_deployment, project: project, project_source_repository: storefront, repository_full_name: "acme/storefront", release: "web-2026.06.18", commit_sha: "abc1234")
    create(:project_deployment, project: project, project_source_repository: api, repository_full_name: "acme/api", release: "api-2026.06.18", commit_sha: "def5678")

    get deployments_project_path(project), params: { repository: "acme/api", q: "api" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("api-2026.06.18")
    expect(response.body).not_to include("web-2026.06.18")
  end
end
