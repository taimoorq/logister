# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectSourceRepositoryAutoConnector do
  it "connects the synced repository whose name matches the project" do
    project = create(:project, slug: "newsfeedreader", name: "News Feed Reader")
    installation = create(:github_installation)
    create(:github_repository, github_installation: installation, full_name: "taimoorq/logister")
    repository = create(:github_repository, github_installation: installation, full_name: "taimoorq/newsfeedreader")

    result = described_class.call(project: project, github_repositories: installation.github_repositories.to_a)

    expect(result).to be_connected
    source_repository = project.source_repositories.find_by!(full_name: "taimoorq/newsfeedreader")
    expect(source_repository.github_repository).to eq(repository)
    expect(source_repository.github_installation).to eq(installation)
    expect(source_repository).to be_enabled
  end

  it "connects the sole synced repository when there is no name match" do
    project = create(:project, slug: "checkout")
    repository = create(:github_repository, full_name: "acme/storefront")

    result = described_class.call(project: project, github_repositories: [ repository ])

    expect(result).to be_connected
    expect(project.source_repositories.find_by!(full_name: "acme/storefront").github_repository).to eq(repository)
  end

  it "links an existing manual mapping to synced GitHub repository metadata" do
    project = create(:project)
    source_repository = create(:project_source_repository, project: project, full_name: "acme/storefront", github_repository: nil)
    github_repository = create(:github_repository, full_name: "acme/storefront", external_id: 123_456, default_branch: "trunk")

    result = described_class.call(project: project, github_repositories: [ github_repository ])

    expect(result).to be_connected
    source_repository.reload
    expect(source_repository.github_repository).to eq(github_repository)
    expect(source_repository.github_installation).to eq(github_repository.github_installation)
    expect(source_repository.external_id).to eq(123_456)
  end

  it "does not create a mapping when multiple synced repositories are ambiguous" do
    project = create(:project, slug: "api")
    repositories = [
      create(:github_repository, full_name: "acme/storefront"),
      create(:github_repository, full_name: "acme/worker")
    ]

    result = described_class.call(project: project, github_repositories: repositories)

    expect(result).not_to be_connected
    expect(project.source_repositories).to be_empty
  end
end
