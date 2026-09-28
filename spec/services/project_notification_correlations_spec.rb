require "rails_helper"

RSpec.describe ProjectNotificationCorrelations do
  it "resolves related records for each recipient at send time without persisting peer metadata" do
    user = create(:user)
    project = create(:project, user:, cross_project_correlations_enabled: true)
    backend = create(:project, user:, cross_project_correlations_enabled: true)
    allow(ProjectCorrelationPolicy).to receive(:enabled?).and_return(true)
    link = ProjectLink.connect!(actor: user, source: project, target: backend, environment_pairs: [ { "source" => "production", "target" => "production" } ])
    event = create(:ingest_event, :grouped, project:, context: { trace_id: "shared" })
    create(:ingest_event, project: backend, context: { trace_id: "shared", route: "POST /orders" })
    delivery = create(:email_notification_delivery, project:, user:, error_group: event.reload.error_group)
    expect(described_class.call(delivery).pluck(:project_uuid)).to eq([ backend.uuid ])
    expect(ProjectErrorMailer.first_occurrence(delivery).body.encoded).to include("Related request evidence", "POST /orders")
    expect(delivery.reload.metadata.to_json).not_to include(backend.uuid, backend.name)
    backend.update!(user: create(:user))
    expect(described_class.call(delivery)).to be_empty
    expect(ProjectErrorMailer.first_occurrence(delivery).body.encoded).not_to include(backend.name)
    link.destroy!
    expect(described_class.call(delivery)).to be_empty
  end
end
