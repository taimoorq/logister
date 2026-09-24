require "rails_helper"

RSpec.describe "Project connections form", type: :request do
  let(:owner) { users(:one) }
  let(:backend) { create(:project, user: owner, name: "StoreStuff.app") }
  let(:android) { create(:project, :android, user: owner, name: "StoreStuff Android") }
  let(:ios) { create(:project, :ios, user: owner, name: "StoreStuff iOS") }

  before { sign_in owner }

  def connection_params(peer, **attributes)
    { direction: "incoming", peer_project_uuid: peer.uuid, source_environment: "production", target_environment: "production" }.merge(attributes)
  end

  it "starts at the backend with labeled, styled project choices and no self or inaccessible project" do
    android
    ios
    archived = create(:project, :archived, user: owner)
    purging = create(:project, user: owner, purge_requested_at: Time.current)
    get project_project_links_path(backend)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#link-project-title").text).to eq("Link an app to this backend")
    picker = html.at_css("select#peer_project_uuid.form-input")
    expect(picker.at_css("option[value='#{android.uuid}']").text).to include(android.name, "Android", android.slug)
    expect(picker.at_css("option[value='#{ios.uuid}']").text).to include(ios.name, "iOS", ios.slug)
    [ backend, archived, purging, projects(:two) ].each do |project|
      expect(picker.at_css("option[value='#{project.uuid}']")).to be_nil
    end
  end

  it "links both mobile projects from the backend with the correct request direction and audits" do
    [ android, ios ].each do |mobile|
      expect {
        post project_project_links_path(backend), params: connection_params(mobile, source_environment: "release")
      }.to change(ProjectLink, :count).by(1).and change(ProjectLinkAudit, :count).by(1)
      expect(response).to have_http_status(:see_other)
      expect(ProjectLink.last).to have_attributes(source_project_id: mobile.id, target_project_id: backend.id,
        environment_pairs: [ { "source" => "release", "target" => "production" } ])
    end
  end

  it "keeps mobile entry pointing to its backend and accepts the reviewed outgoing form" do
    ios
    get project_project_links_path(android)
    expect(response.body).to include("Link this app to a backend")
    expect(Nokogiri::HTML(response.body).at_css("select option[value='#{ios.uuid}']")).to be_nil
    expect(response.body).not_to include("Link an app instead")
    post project_project_links_path(android), params: connection_params(backend, direction: "outgoing")
    expect(ProjectLink.last).to have_attributes(source_project_id: android.id, target_project_id: backend.id)
  end

  it "rejects reversed mobile-as-backend connections" do
    expect {
      post project_project_links_path(android), params: connection_params(backend)
    }.not_to change(ProjectLink, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Choose a backend project to receive requests from the mobile app.")
  end

  it "offers each project's own recent environment names without silently choosing production" do
    create(:ingest_event, project: android, context: { environment: "release" })
    create(:trace_span, project: backend, context: { environment: "prod-eu" })
    create(:ingest_event, project: projects(:two), context: { environment: "secret-env" })
    get project_project_links_path(backend), params: { peer_project_uuid: android.uuid, direction: "incoming" }
    html = Nokogiri::HTML(response.body)
    app_select = html.at_css("select#source_environment")
    backend_select = html.at_css("select#target_environment")
    expect(app_select.text).to include("release", "Other environment")
    expect(app_select.text).not_to include("prod-eu", "secret-env")
    expect(backend_select.text).to include("prod-eu")
    expect(backend_select.text).not_to include("release", "secret-env")
    expect(html.css("select option[selected]").map { |option| option["value"] }).to all(eq(""))
  end

  it "preserves project, direction and custom input after an invalid submission, then recovers" do
    attributes = connection_params(android, source_environment: "__custom__", custom_source_environment: "bad name")
    expect { post project_project_links_path(backend), params: attributes }.not_to change(ProjectLink, :count)
    expect(response).to have_http_status(:unprocessable_content)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("input#peer_project_uuid")["value"]).to eq(android.uuid)
    expect(html.at_css("input#direction")["value"]).to eq("incoming")
    expect(html.at_css("input#custom_source_environment")["value"]).to eq("bad name")
    expect(html.at_css("select#source_environment option[selected]")["value"]).to eq("__custom__")
    post project_project_links_path(backend), params: attributes.merge(custom_source_environment: "qa-west")
    expect(response).to have_http_status(:see_other)
    expect(ProjectLink.last.environment_pairs).to eq([ { "source" => "qa-west", "target" => "production" } ])
  end

  it "disables linked choices and handles repeated submissions without a duplicate or second audit" do
    post project_project_links_path(backend), params: connection_params(android)
    expect {
      post project_project_links_path(backend), params: connection_params(android)
    }.not_to change(ProjectLinkAudit, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("These projects are already linked")
    get project_project_links_path(backend)
    expect(Nokogiri::HTML(response.body).at_css("option[value='#{android.uuid}']")["disabled"]).to be_present
  end

  it "rejects tampered, archived, self, and no-longer-managed project selections in both steps" do
    [ projects(:two), create(:project, :archived, user: owner), backend ].each do |peer|
      sign_in owner
      get project_project_links_path(backend), params: { peer_project_uuid: peer.uuid }
      expect(response).to have_http_status(:not_found)
      sign_in owner
      expect { post project_project_links_path(backend), params: connection_params(peer) }.not_to change(ProjectLink, :count)
      expect(response).to have_http_status(:not_found)
    end
    sign_in owner
    get project_project_links_path(backend), params: { peer_project_uuid: android.uuid }
    expect(response).to have_http_status(:ok)
    android.update!(user: users(:two))
    post project_project_links_path(backend), params: connection_params(android)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects missing environments and an unknown direction" do
    expect {
      post project_project_links_path(backend), params: connection_params(android, source_environment: "", direction: "sideways")
    }.not_to change(ProjectLink, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end
end
