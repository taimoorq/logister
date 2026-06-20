# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectDeployment, type: :model do
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs }

  it "normalizes repository URLs and commit SHAs" do
    deployment = build(
      :project_deployment,
      repository_full_name: " https://github.com/acme/storefront.git ",
      commit_sha: "ABC1234",
      branch: "refs/heads/main"
    )

    expect(deployment).to be_valid
    expect(deployment.repository_full_name).to eq("acme/storefront")
    expect(deployment.commit_sha).to eq("abc1234")
    expect(deployment.branch).to eq("main")
  end

  it "rejects invalid commit SHAs" do
    deployment = build(:project_deployment, commit_sha: "not-a-sha")

    expect(deployment).not_to be_valid
    expect(deployment.errors[:commit_sha]).to include("must be a 7 to 40 character commit SHA")
  end

  it "resolves the commit for a project, repository, release, and environment" do
    project = create(:project)
    repository = create(:project_source_repository, project: project, full_name: "acme/storefront")
    create(
      :project_deployment,
      project: project,
      project_source_repository: repository,
      repository_full_name: "acme/storefront",
      release: "2026.06.18",
      environment: "staging",
      commit_sha: "abc1234"
    )

    commit = described_class.resolve_commit(
      project: project,
      repository: repository,
      release: "2026.06.18",
      environment: "staging"
    )

    expect(commit).to eq("abc1234")
  end

  it "builds GitHub commit, pull request, release, and compare URLs from metadata" do
    project = create(:project)
    repository = create(:project_source_repository, project: project, full_name: "acme/storefront")
    previous = create(
      :project_deployment,
      project: project,
      project_source_repository: repository,
      repository_full_name: "acme/storefront",
      release: "2026.06.17",
      commit_sha: "abc1234"
    )
    deployment = create(
      :project_deployment,
      project: project,
      project_source_repository: repository,
      repository_full_name: "acme/storefront",
      release: "2026.06.18",
      commit_sha: "def5678",
      metadata: {
        "pull_request_number" => 42,
        "release_tag" => "v2026.06.18"
      }
    )

    expect(deployment.github_commit_url).to eq("https://github.com/acme/storefront/commit/def5678")
    expect(deployment.pull_request_label).to eq("PR #42")
    expect(deployment.pull_request_url).to eq("https://github.com/acme/storefront/pull/42")
    expect(deployment.release_url).to eq("https://github.com/acme/storefront/releases/tag/v2026.06.18")
    expect(deployment.compare_url(previous)).to eq("https://github.com/acme/storefront/compare/abc1234...def5678")
  end

  it "queues a release summary notification when a deployment is created" do
    deployment = create(:project_deployment)

    expect(ProjectReleaseNotificationJob).to have_been_enqueued.with(deployment.id)
  end
end
