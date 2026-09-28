require "rails_helper"

RSpec.describe "Connected request details", type: :request do
  before do
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    sign_in users(:one)
  end

  it "opens a specific span and preserves exact occurrence navigation" do
    project = create(:project, user: users(:one), cross_project_correlations_enabled: true)
    span = create(:trace_span, project:, context: { environment: "production", http: { status_code: 503, method: "POST", failure_kind: "http" }, app: { version_name: "2.3", version_code: "17" } })
    error = create(:ingest_event, :grouped, project:, occurred_at: Time.current.change(usec: 123456), context: { trace_id: span.trace_id, environment: "production" })
    get project_request_path(project, span)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("HTTP 503", "180.5 ms", "2.3 / 17", span.span_id, "related_requests")
    expect(response.body).to include(project_event_path(project, error))
    get project_request_path(project, span), headers: { "Turbo-Frame" => "related_requests" }
    expect(response.body).to include('id="related_requests"')
  end

  it "denies another project's request and disabled correlation reads" do
    project = create(:project, user: users(:two), cross_project_correlations_enabled: true)
    span = create(:trace_span, project:)
    get project_request_path(project, span)
    expect(response).to have_http_status(:not_found)
    project.update!(user: users(:one))
    sign_in users(:one)
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(false)
    get project_request_path(project, span)
    expect(response).to have_http_status(:not_found)
  end
  it "keeps invalid-window and timeout responses inside the request frame" do
    project = create(:project, user: users(:one), cross_project_correlations_enabled: true)
    span = create(:trace_span, project:)
    get project_request_path(project, span, from: "bad"), headers: { "Turbo-Frame" => "related_requests" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('id="related_requests"', 'name="occurred_at"', "ISO 8601")
    allow(ProjectCorrelationsQuery).to receive(:call).and_raise(ActiveRecord::QueryCanceled)
    get project_request_path(project, span), headers: { "Turbo-Frame" => "related_requests" }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include('id="related_requests"', "took too long")
  end
end
