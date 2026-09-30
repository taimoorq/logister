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

RSpec.describe "Uploading build artifacts from Releases", type: :request do
  let(:owner) { users(:one) }

  def document
    Nokogiri::HTML.parse(response.body)
  end

  before { sign_in owner }

  it "lets a manager upload an R8 mapping on the Artifacts page" do
    project = create(:project, :android, user: owner)

    get artifacts_project_path(project)

    card = document.at_css("#upload-artifact")
    expect(card.at_css("h3").text).to eq("Upload an R8 mapping")
    form = card.at_css("form[action='#{project_android_mapping_files_path(project)}']")
    expect(form.at_css("input[type='file'][name='android_mapping_file[upload]']")).to be_present
    expect(form.at_css("input[name='setup_return']")).to be_nil
    expect(document.at_css("a.btn-primary[href='#upload-artifact']").text).to eq("Upload a mapping")
  end

  it "lets a manager upload a dSYM archive on the Artifacts page" do
    project = create(:project, :ios, user: owner)

    get artifacts_project_path(project)

    card = document.at_css("#upload-artifact")
    expect(card.at_css("h3").text).to eq("Upload a dSYM archive")
    expect(card.at_css("form[action='#{project_apple_symbol_artifacts_path(project)}'] input[name='apple_symbol_artifact[binary_uuid]']")).to be_present
  end

  it "shows a member who cannot manage the project the inventory, without an upload form" do
    project = create(:project, :android)
    viewer = create(:user)
    create(:project_membership, project: project, user: viewer, role: :viewer)
    sign_out owner
    sign_in viewer

    get artifacts_project_path(project)

    expect(response).to have_http_status(:success)
    expect(document.at_css("#upload-artifact")).to be_nil
    expect(document.text).to include("Manager access required").or include("Artifact inventory")
  end

  it "leaves a pointer in Settings instead of a second upload form" do
    android = create(:project, :android, user: owner)
    get settings_project_path(android, section: "integrations")
    expect(document.at_css("#android-mappings a").text).to include("Releases › Artifacts")
    expect(document.at_css("form[action='#{project_android_mapping_files_path(android)}']")).to be_nil

    ios = create(:project, :ios, user: owner)
    get settings_project_path(ios, section: "integrations")
    expect(document.at_css("#apple-symbols a")["href"]).to eq(artifacts_project_path(ios))
    expect(document.at_css("form[action='#{project_apple_symbol_artifacts_path(ios)}']")).to be_nil
  end

  it "sends a failed mapping upload back to the upload form" do
    project = create(:project, :android, user: owner)

    post project_android_mapping_files_path(project), params: { android_mapping_file: { package_name: "", version_code: "" } }

    expect(response).to redirect_to(artifacts_project_path(project, anchor: "upload-artifact"))
    expect(flash[:alert]).to be_present
  end

  it "still offers the same upload inside the setup path" do
    project = create(:project, :android, user: owner)

    get setup_step_project_path(project, group: "actionable", step: "mapping")

    form = document.at_css("form[action='#{project_android_mapping_files_path(project)}']")
    expect(form.at_css("input[name='setup_return'][value='actionable/mapping']")).to be_present
  end
end
