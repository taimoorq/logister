require "rails_helper"

RSpec.describe "Project correlations", type: :request do
  it "requires management of both endpoints and audits connection removal" do
    source = create(:project, user: users(:one))
    target = create(:project, user: users(:two))
    sign_in users(:one)
    post project_project_links_path(source), params: { target_project_uuid: target.uuid, source_environment: "production", target_environment: "production" }
    expect(response).to have_http_status(:not_found)
    target.update!(user: users(:one))
    sign_in users(:one)
    expect {
      post project_project_links_path(source), params: { target_project_uuid: target.uuid, source_environment: "production", target_environment: "production" }
    }.to change(ProjectLink, :count).by(1).and change(ProjectLinkAudit, :count).by(1)
    link = ProjectLink.last
    target.update!(user: users(:two))
    delete project_project_link_path(source, link)
    expect(response).to have_http_status(:redirect)
    expect(ProjectLinkAudit.last.action).to eq("disconnected")
  end

  it "renders direct and frame navigation without leaking inaccessible projects" do
    project = create(:project, user: users(:one))
    project.update!(cross_project_correlations_enabled: true)
    event = create(:ingest_event, project:, context: { trace_id: "test-trace" })
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    sign_in users(:one)
    get correlations_project_event_path(project, event)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="related_requests"', "No related requests found")
    get project_project_links_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(projects(:two).name)
  end
  it "requires CLI read scopes and intersects the token project allowlist" do
    user = users(:one)
    mobile = create(:project, user:, cross_project_correlations_enabled: true)
    backend = create(:project, user:, cross_project_correlations_enabled: true)
    ProjectLink.connect!(actor: user, source: mobile, target: backend, environment_pairs: [ { "source" => "production", "target" => "production" } ])
    event = create(:ingest_event, project: mobile, context: { trace_id: "synthetic-cli-trace" })
    related = create(:ingest_event, project: backend, context: event.context)
    path = "/api/v1/cli/projects/#{mobile.uuid}/events/#{event.uuid}/correlations"
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    key = create(:api_key, project: mobile, user:)
    get path, headers: { "Authorization" => "Bearer #{key.plain_token}" }
    expect(response).to have_http_status(:unauthorized)
    token = create(:cli_access_token, user:, scopes: [ "events:read" ])
    get path, headers: { "Authorization" => "Bearer #{token.plain_token}" }
    expect(response).to have_http_status(:forbidden)
    token.update!(scopes: CliAccessToken::READ_SCOPES, all_projects: false, allowed_project_ids: [ mobile.id ])
    get path, headers: { "Authorization" => "Bearer #{token.plain_token}" }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(related.uuid, backend.uuid, backend.name)
    token.update!(allowed_project_ids: [ mobile.id, backend.id ])
    get path, headers: { "Authorization" => "Bearer #{token.plain_token}" }
    expect(response.parsed_body.fetch("items").map { |row| row.fetch("uuid") }).to include(related.uuid)
  end
end
