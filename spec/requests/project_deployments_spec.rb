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

RSpec.describe "Release health on Releases", type: :request do
  let(:owner) { users(:one) }
  let(:project) { create(:project, :ruby, user: owner) }
  let(:frame_headers) { { "Turbo-Frame" => "release_health" } }

  before { sign_in owner }

  it "loads release health on the Releases page for a server project, and no longer on Performance" do
    get deployments_project_path(project)

    frame = Nokogiri::HTML.parse(response.body).at_css("turbo-frame#release_health")
    expect(frame["src"]).to eq(deployments_release_health_project_path(project))
    expect(frame["loading"]).to eq("lazy")

    get performance_project_path(project)
    expect(response.body).not_to include("release_health")
  end

  it "leaves release health off a mobile project, whose Releases page shows observed builds" do
    get deployments_project_path(create(:project, :ios, user: owner))

    expect(Nokogiri::HTML.parse(response.body).at_css("turbo-frame#release_health")).to be_nil
  end

  it "answers the frame with the release cards it finds" do
    api_key = create(:api_key, project: project, user: owner)
    create(:ingest_event, project: project, api_key: api_key, event_type: :error, level: "error",
                          message: "Boom", context: { release: "1.4.2" })

    get deployments_release_health_project_path(project), headers: frame_headers

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css("turbo-frame#release_health")).to be_present
    expect(document.text).to include("Release health", "1.4.2")
  end

  it "renders an empty frame when nothing has been released" do
    get deployments_release_health_project_path(project), headers: frame_headers

    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css("turbo-frame#release_health")).to be_present
    expect(document.text.strip).to be_empty
  end

  it "sends a direct visit, or a request for another frame, to the page that hosts it" do
    get deployments_release_health_project_path(project)
    expect(response).to redirect_to(deployments_project_path(project, anchor: "release_health"))

    get deployments_release_health_project_path(project), headers: { "Turbo-Frame" => "other_frame" }
    expect(response).to redirect_to(deployments_project_path(project, anchor: "release_health"))
  end

  it "is only for people who can open the project" do
    get deployments_release_health_project_path(create(:project, :ruby)), headers: frame_headers

    expect(response).to have_http_status(:not_found)
  end
end
