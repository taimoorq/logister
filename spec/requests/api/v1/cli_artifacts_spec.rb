# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CLI mobile artifact uploads", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  def authorization_for(project, scopes: [ "artifacts:write" ], token_user: user)
    token = create(:cli_access_token, user: token_user, scopes: scopes, all_projects: false, allowed_project_ids: [ project.id ])
    { "Authorization" => "Bearer #{token.plain_token}" }
  end

  it "uploads an Android mapping with manager and write-scope enforcement" do
    project = create(:project, :android, user: user)
    file = fixture_file_upload("android_mapping.txt", "text/plain")

    expect do
      post "/api/v1/cli/projects/#{project.uuid}/artifacts/android-mapping",
           params: { package_name: "com.acme.shop", version_name: "1.4.0", version_code: "42", file: file },
           headers: authorization_for(project)
    end.to change(project.android_mapping_files, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include("artifact" => "android_mapping", "version_code" => "42", "status" => "available", "coverage_refresh" => "queued")
    expect(MobileArtifactCoverageRefreshJob).to have_been_enqueued.with(project.id, "android")
  end

  it "uploads an iOS dSYM for an archived forensic project and queues verification" do
    project = create(:project, :ios, :archived, user: user)
    zip = Tempfile.new([ "symbols", ".zip" ])
    zip.binmode
    zip.write("PK\x03\x04symbol-data")
    zip.rewind
    file = Rack::Test::UploadedFile.new(zip.path, "application/zip", true, original_filename: "Shop.app.dSYM.zip")

    expect do
      post "/api/v1/cli/projects/#{project.uuid}/artifacts/apple-dsym",
           params: {
             app_identifier: "com.acme.shop",
             version_name: "1.4.0",
             version_code: "42",
             binary_uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
             architecture: "arm64",
             file: file
           },
           headers: authorization_for(project)
    end.to change(project.apple_symbol_artifacts, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include("artifact" => "apple_dsym", "verification" => "queued")
    expect(AppleSymbolArtifactProcessingJob).to have_been_enqueued
  ensure
    zip&.close!
  end

  it "rejects read-only tokens, viewers, and the wrong platform" do
    project = create(:project, :android, user: user)
    file = fixture_file_upload("android_mapping.txt", "text/plain")

    post "/api/v1/cli/projects/#{project.uuid}/artifacts/android-mapping",
         params: { package_name: "com.acme.shop", version_code: "42", file: file },
         headers: authorization_for(project, scopes: [ "projects:read" ])
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["code"]).to eq("insufficient_scope")

    viewer = create(:user)
    create(:project_membership, project: project, user: viewer, role: :viewer)
    post "/api/v1/cli/projects/#{project.uuid}/artifacts/android-mapping",
         params: { package_name: "com.acme.shop", version_code: "42", file: fixture_file_upload("android_mapping.txt", "text/plain") },
         headers: authorization_for(project, token_user: viewer)
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["code"]).to eq("project_manager_required")

    post "/api/v1/cli/projects/#{project.uuid}/artifacts/apple-dsym",
         params: {},
         headers: authorization_for(project)
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["code"]).to eq("unsupported_project_type")
  end
end
