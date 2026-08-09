# frozen_string_literal: true

require "rails_helper"

RSpec.describe EvidenceAccessAudit do
  it "requires a project manager, bounded reason, and no evidence payload" do
    project = create(:project)
    viewer = create(:user)
    create(:project_membership, project: project, user: viewer, role: :viewer)
    audit = described_class.new(
      project: project,
      user: viewer,
      ingest_event_uuid: SecureRandom.uuid,
      ingest_event_occurred_at: Time.current,
      action: "download_unredacted_stored_evidence",
      reason: "Investigating production checkout",
      request_metadata: { "ip_hmac" => "digest" }
    )

    expect(audit).not_to be_valid
    expect(audit.errors[:user]).to include("must manage the project")
    expect(audit.request_metadata.to_json).not_to include("context", "evidence")
  end
end
