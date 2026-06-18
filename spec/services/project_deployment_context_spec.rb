# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectDeploymentContext do
  it "finds the deployment that happened before the error first appeared" do
    project = create(:project)
    repository = create(:project_source_repository, project: project, full_name: "acme/storefront")
    previous = create(
      :project_deployment,
      project: project,
      project_source_repository: repository,
      repository_full_name: "acme/storefront",
      release: "2026.06.17",
      commit_sha: "abc1234",
      deployed_at: Time.zone.parse("2026-06-17T12:00:00Z")
    )
    deployment = create(
      :project_deployment,
      project: project,
      project_source_repository: repository,
      repository_full_name: "acme/storefront",
      release: "2026.06.18",
      commit_sha: "def5678",
      deployed_at: Time.zone.parse("2026-06-18T12:00:00Z")
    )
    group = create(
      :error_group,
      project: project,
      stage: "production",
      first_seen_at: Time.zone.parse("2026-06-18T12:45:00Z")
    )

    result = described_class.call(project: project, group: group)

    expect(result.deployment).to eq(deployment)
    expect(result.previous_deployment).to eq(previous)
    expect(result.started_after).to be(true)
    expect(result.minutes_after).to eq(45)
  end

  it "prefers an exact release match from the event context" do
    project = create(:project)
    create(:project_source_repository, project: project, full_name: "acme/storefront")
    older = create(:project_deployment, project: project, repository_full_name: "acme/storefront", release: "2026.06.17", commit_sha: "abc1234")
    release_deployment = create(:project_deployment, project: project, repository_full_name: "acme/storefront", release: "2026.06.18", commit_sha: "def5678")
    group = create(:error_group, project: project, first_seen_at: older.deployed_at + 5.minutes)
    event = create(:ingest_event, project: project, context: {
      "release" => "2026.06.18",
      "environment" => "production",
      "repository" => "acme/storefront"
    })

    result = described_class.call(project: project, group: group, event: event)

    expect(result.deployment).to eq(release_deployment)
    expect(result).to be_exact_release
  end
end
