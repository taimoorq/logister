require "rails_helper"

RSpec.describe "Connected impact", type: :request do
  it "serves direct, frame and bounded export views under current permissions" do
    sign_in users(:one)
    project = create(:project, user: users(:one), cross_project_correlations_enabled: true)
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    get connections_project_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Connected impact", "No related occurrences", 'id="connected_evidence"')
    get connections_project_path(project), headers: { "Turbo-Frame" => "connected_evidence" }
    expect(response).to have_http_status(:ok)
    get connections_project_path(project, format: :json)
    expect(response.parsed_body).to include("pairs" => [], "anchor_count" => 0)
    expect(response.headers['Content-Disposition']).to include("attachment")
    get connections_project_path(project, from: 10.days.ago.iso8601)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("up to seven days")
  end
end
