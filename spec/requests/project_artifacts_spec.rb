# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project artifacts", type: :request do
  before { sign_in users(:one) }

  it "renders Android inventory in the shared mobile shell without artifact contents" do
    project = create(:project, :android, user: users(:one), name: "Android Artifacts")
    mapping = create(:android_mapping_file, project:, uploaded_by: users(:one))

    get artifacts_project_path(project)

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css(".project-command-panel")["data-project-page"]).to eq("artifacts")
    expect(document.css("a[aria-current='page']").map(&:text).join).to include("Artifacts")
    expect(document.text).to include("R8 mapping artifacts", "Observed-build coverage", "Mapping validated", mapping.filename)
    expect(response.body).not_to include(mapping.content)
  end

  it "keeps archived iOS forensic artifact operations explicit and recoverable" do
    project = create(:project, :ios, user: users(:one), name: "Archived iOS Artifacts")
    artifact = create(:apple_symbol_artifact, project:, status: "failed")
    project.archive!

    get artifacts_project_path(project)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("This project is archived", "Verification failed", "Verify again", "Remove")

    post process_artifact_project_apple_symbol_artifact_path(project, artifact), params: { return_to: "artifacts" }
    expect(response).to redirect_to(artifacts_project_path(project))
  end

  it "allows viewers to inspect metadata but not mutate artifacts" do
    project = create(:project, :ios, user: users(:one), name: "Shared iOS Artifacts")
    create(:apple_symbol_artifact, project:, status: "verified")
    create(:project_membership, project:, user: users(:two), role: :viewer)
    sign_out users(:one)
    sign_in users(:two)

    get artifacts_project_path(project)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("UUID verified", "Manager access required")
    expect(response.body).not_to include("Verify again", ">Remove<", "Upload in integration settings")
  end

  it "does not expose the mobile artifact route to service projects" do
    project = create(:project, user: users(:one))

    get artifacts_project_path(project)

    expect(response).to have_http_status(:not_found)
  end
end
