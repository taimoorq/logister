# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Android mapping files", type: :request do
  let(:project) { create(:project, :android, user: users(:one)) }

  before { sign_in users(:one) }

  it "uploads a private release-scoped mapping and lists only its metadata" do
    upload = fixture_file_upload("android_mapping.txt", "text/plain")

    expect do
      post project_android_mapping_files_path(project), params: {
        android_mapping_file: {
          package_name: "com.acme.shop",
          version_name: "1.4.0",
          version_code: "42",
          release: "1.4.0+42",
          upload: upload
        }
      }
    end.to change(project.android_mapping_files, :count).by(1)

    mapping = project.android_mapping_files.sole
    expect(mapping).to have_attributes(package_name: "com.acme.shop", version_code: "42")
    expect(mapping.content).to include("CartStore")
    expect(response).to redirect_to(settings_project_path(project, section: "integrations", anchor: "android-mappings"))

    get settings_project_path(project, section: "integrations")
    expect(response.body).to include("android_mapping.txt", mapping.checksum_sha256.first(12))
    expect(response.body).not_to include("com.acme.shop.storage.CartStore -&gt; a")
  end

  it "does not let a member without project management access upload mappings" do
    member = create(:user)
    create(:project_membership, project: project, user: member, role: :viewer)
    sign_in member

    post project_android_mapping_files_path(project), params: { android_mapping_file: { package_name: "com.acme.shop", version_code: "42" } }

    expect(response).to have_http_status(:not_found)
  end
end
