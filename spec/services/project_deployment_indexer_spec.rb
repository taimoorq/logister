# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectDeploymentIndexer do
  it "indexes deployments from event release and git context" do
    project = create(:project)
    create(:project_source_repository, project: project, full_name: "acme/storefront")
    event = create(:ingest_event, project: project, context: {
      "release" => "2026.06.18",
      "environment" => "production",
      "repository" => "https://github.com/acme/storefront.git",
      "commit_sha" => "ABC1234",
      "branch" => "refs/heads/main"
    })

    result = described_class.from_event(event)

    expect(result).to be_indexed
    deployment = ProjectDeployment.last
    expect(deployment).to have_attributes(
      project_id: project.id,
      repository_full_name: "acme/storefront",
      release: "2026.06.18",
      environment: "production",
      commit_sha: "abc1234",
      branch: "main",
      source: "telemetry"
    )
  end

  it "uses the sole enabled source repository when telemetry omits the repository name" do
    project = create(:project)
    create(:project_source_repository, project: project, full_name: "acme/storefront")
    event = create(:ingest_event, project: project, context: {
      "release" => "2026.06.18",
      "commit_sha" => "abc1234"
    })

    result = described_class.from_event(event)

    expect(result).to be_indexed
    expect(result.deployment.repository_full_name).to eq("acme/storefront")
  end

  it "skips telemetry that does not identify a unique repository" do
    project = create(:project)
    create(:project_source_repository, project: project, full_name: "acme/storefront")
    create(:project_source_repository, project: project, full_name: "acme/api")
    event = create(:ingest_event, project: project, context: {
      "release" => "2026.06.18",
      "commit_sha" => "abc1234"
    })

    expect(described_class.from_event(event)).not_to be_indexed
    expect(ProjectDeployment.where(project: project)).to be_empty
  end

  it "updates an existing deployment mapping" do
    project = create(:project)
    repository = create(:project_source_repository, project: project, full_name: "acme/storefront")
    create(
      :project_deployment,
      project: project,
      project_source_repository: repository,
      repository_full_name: "acme/storefront",
      release: "2026.06.18",
      environment: "production",
      commit_sha: "abc1234"
    )

    result = described_class.from_payload(
      project: project,
      payload: {
        release: "2026.06.18",
        environment: "production",
        repository: "acme/storefront",
        commit_sha: "def5678"
      }
    )

    expect(result).to be_indexed
    expect(ProjectDeployment.where(project: project).count).to eq(1)
    expect(result.deployment.reload.commit_sha).to eq("def5678")
  end

  it "stores GitHub pull request and release metadata from deployment payloads" do
    project = create(:project)
    create(:project_source_repository, project: project, full_name: "acme/storefront")

    result = described_class.from_payload(
      project: project,
      payload: {
        release: "2026.06.18",
        environment: "production",
        repository: "acme/storefront",
        commit_sha: "def5678",
        ref: "refs/pull/42/merge",
        github: {
          release: {
            tag_name: "v2026.06.18",
            html_url: "https://github.com/acme/storefront/releases/tag/v2026.06.18"
          },
          workflow_run_url: "https://github.com/acme/storefront/actions/runs/123"
        }
      }
    )

    expect(result).to be_indexed
    expect(result.deployment.metadata).to include(
      "pull_request_number" => "42",
      "pull_request_url" => "https://github.com/acme/storefront/pull/42",
      "release_tag" => "v2026.06.18",
      "release_url" => "https://github.com/acme/storefront/releases/tag/v2026.06.18",
      "workflow_run_url" => "https://github.com/acme/storefront/actions/runs/123"
    )
  end

  it "returns validation errors for incomplete deployment API payloads" do
    result = described_class.from_payload(project: create(:project), payload: { release: "2026.06.18" })

    expect(result).not_to be_indexed
    expect(result.errors).to include("Repository can't be blank", "Commit sha can't be blank")
  end
end
