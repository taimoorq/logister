# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Apple symbol artifacts", type: :request do
  include ActiveJob::TestHelper

  let(:project) { create(:project, :ios, user: users(:one)) }

  before { sign_in users(:one) }

  it "uploads a private archive, exposes metadata only, and queues UUID verification" do
    Tempfile.create([ "AcmeShop.dSYM", ".zip" ]) do |file|
      file.binmode
      file.write("PK\x03\x04private-symbol-fixture")
      file.flush
      upload = Rack::Test::UploadedFile.new(
        file.path,
        "application/zip",
        true,
        original_filename: "AcmeShop.dSYM.zip"
      )

      expect do
        post project_apple_symbol_artifacts_path(project), params: {
          apple_symbol_artifact: {
            app_identifier: "com.acme.shop",
            version_name: "4.2.0",
            version_code: "310",
            binary_uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            architecture: "arm64",
            upload: upload
          }
        }
      end.to change(project.apple_symbol_artifacts, :count).by(1)
        .and have_enqueued_job(AppleSymbolArtifactProcessingJob)
    end

    artifact = project.apple_symbol_artifacts.sole
    expect(artifact).to have_attributes(
      binary_uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      status: "uploaded",
      filename: "AcmeShop.dSYM.zip"
    )
    expect(artifact.storage_key).to include("apple-symbols", "project=#{project.uuid}")
    expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "apple-symbols"))

    get settings_project_path(project, section: "integrations")
    expect(response.body).to include("AcmeShop.dSYM.zip", artifact.binary_uuid, "Uploaded")
    expect(response.body).not_to include("private-symbol-fixture")

    artifact.destroy!
  end

  it "does not allow a viewer to upload symbols" do
    viewer = create(:user)
    create(:project_membership, project: project, user: viewer, role: :viewer)
    sign_in viewer

    post project_apple_symbol_artifacts_path(project), params: { apple_symbol_artifact: {} }

    expect(response).to have_http_status(:not_found)
  end
end
