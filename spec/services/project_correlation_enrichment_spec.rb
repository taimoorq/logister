require "rails_helper"

RSpec.describe "Correlation enrichment" do
  it "returns bounded issue and mobile metadata without arbitrary context" do
    user = create(:user)
    app = create(:project, :ios, user:, cross_project_correlations_enabled: true)
    backend = create(:project, user:, cross_project_correlations_enabled: true)
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    ProjectLink.connect!(actor: user, source: app, target: backend, environment_pairs: [ { "source" => "production", "target" => "live" } ])
    anchor = create(:ingest_event, project: backend, context: { trace_id: "shared", environment: "live" })
    error = create(:ingest_event, :grouped, project: app, context: { trace_id: "shared", environment: "production", app: { version_name: "4.2", version_code: "42" }, device: { model: "Phone" }, os: { version: "20" }, private_payload: "not-exportable" })
    result = ProjectCorrelationsQuery.call(principal: user, project: backend, event: anchor)
    row = result[:items].find { |item| item[:uuid] == error.uuid }
    expect(row).to include(app_version: "4.2", build_number: "42", device_model: "Phone", os_version: "20")
    expect(row[:issue]).to include(uuid: error.reload.error_group.uuid, status: "unresolved")
    expect(result.to_json).not_to include("not-exportable")
  end

  it "rejects contradictory requests while retaining genuinely shared traces" do
    anchor = CorrelationContext.new(trace_id: "one", request_id: "same")
    expect(ProjectCorrelationMatch.evidence(anchor, CorrelationContext.new(trace_id: "two", request_id: "same"))).to be_nil
    expect(ProjectCorrelationMatch.evidence(anchor, CorrelationContext.new(trace_id: "one"))).to eq("shared_trace")
  end
end
