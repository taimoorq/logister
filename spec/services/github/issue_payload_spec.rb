# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::IssuePayload do
  it "includes release, deployment, source, and Logister links" do
    project = create(:project, name: "Checkout API")
    group = create(
      :error_group,
      project: project,
      title: "RuntimeError in Checkout",
      fingerprint: "checkout-runtime",
      occurrence_count: 3,
      last_seen_release: "2026.06.18"
    )
    deployment = build(
      :project_deployment,
      project: project,
      repository_full_name: "acme/checkout",
      release: "2026.06.18",
      commit_sha: "def5678"
    )
    deployment_context = ProjectDeploymentContext::Result.new(
      deployment: deployment,
      previous_deployment: nil,
      started_after: true,
      minutes_after: 12,
      exact_release: true
    )

    payload = described_class.call(
      project: project,
      group: group,
      event: nil,
      source_excerpt: { source_url: "https://github.com/acme/checkout/blob/main/app/checkout.rb#L12" },
      deployment_context: deployment_context,
      logister_url: "https://logister.example/projects/#{project.uuid}/inbox?group_uuid=#{group.uuid}"
    )

    expect(payload.title).to eq("[Checkout API] RuntimeError in Checkout")
    expect(payload.body).to include("Occurrences: 3")
    expect(payload.body).to include("Fingerprint: `checkout-runtime`")
    expect(payload.body).to include("Release: `2026.06.18`")
    expect(payload.body).to include("Deployment: `2026.06.18`")
    expect(payload.body).to include("acme/checkout")
    expect(payload.body).to include("def5678")
    expect(payload.body).to include("https://github.com/acme/checkout/blob/main/app/checkout.rb#L12")
    expect(payload.body).to include("https://logister.example/projects/#{project.uuid}/inbox?group_uuid=#{group.uuid}")
  end
end
