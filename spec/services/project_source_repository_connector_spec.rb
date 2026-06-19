# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectSourceRepositoryConnector do
  it "builds manual source repositories" do
    project = create(:project)

    result = described_class.new(
      project: project,
      attributes: {
        provider: "github",
        github_repository_id: "",
        full_name: "acme/storefront",
        enabled: true
      }
    ).build

    expect(result).not_to be_rejected
    expect(result.source_repository.full_name).to eq("acme/storefront")
    expect(result.source_repository.github_repository_id).to be_nil
  end

  it "builds source repositories from linked synced repositories" do
    owner = create(:user)
    project = create(:project, user: owner)
    installation = create(:github_installation, installed_by: owner)
    github_repository = create(:github_repository, github_installation: installation, full_name: "acme/private-api")
    create(:project_github_installation, project: project, github_installation: installation)

    result = described_class.new(
      project: project,
      attributes: {
        provider: "github",
        github_repository_id: github_repository.id,
        enabled: true
      }
    ).build

    expect(result).not_to be_rejected
    expect(result.source_repository.github_repository).to eq(github_repository)
    expect(result.source_repository.github_installation).to eq(installation)
  end

  it "upgrades an existing manual mapping for the same synced repository" do
    owner = create(:user)
    project = create(:project, user: owner)
    installation = create(:github_installation, installed_by: owner)
    github_repository = create(:github_repository, github_installation: installation, full_name: "acme/private-api")
    create(:project_github_installation, project: project, github_installation: installation)
    manual_mapping = create(:project_source_repository, project: project, full_name: "acme/private-api")

    result = described_class.new(
      project: project,
      attributes: {
        provider: "github",
        github_repository_id: github_repository.id,
        enabled: true
      }
    ).build

    expect(result.source_repository).to eq(manual_mapping)
    expect(result.source_repository.github_repository).to eq(github_repository)
    expect(result.source_repository.github_installation).to eq(installation)
  end

  it "rejects synced repositories from installations not linked to the project" do
    owner = create(:user)
    project = create(:project, user: owner)
    github_repository = create(:github_repository, github_installation: create(:github_installation, installed_by: owner))

    result = described_class.new(
      project: project,
      attributes: {
        provider: "github",
        github_repository_id: github_repository.id,
        enabled: true
      }
    ).build

    expect(result).to be_rejected
    expect(result.source_repository.errors[:github_repository]).to include(described_class::ERROR_MESSAGE)
  end

  it "keeps source mappings independent when one installation is linked to multiple projects" do
    owner = create(:user)
    installation = create(:github_installation, installed_by: owner)
    github_repository = create(:github_repository, github_installation: installation, full_name: "acme/private-api")
    first_project = create(:project, user: owner)
    second_project = create(:project, user: owner)
    create(:project_github_installation, project: first_project, github_installation: installation)
    create(:project_github_installation, project: second_project, github_installation: installation)

    first_result = described_class.new(
      project: first_project,
      attributes: {
        provider: "github",
        github_repository_id: github_repository.id,
        runtime_root: "/first",
        enabled: true
      }
    ).build

    second_result = described_class.new(
      project: second_project,
      attributes: {
        provider: "github",
        github_repository_id: github_repository.id,
        runtime_root: "/second",
        enabled: true
      }
    ).build

    expect(first_result.source_repository).not_to eq(second_result.source_repository)
    expect(first_result.source_repository.project).to eq(first_project)
    expect(second_result.source_repository.project).to eq(second_project)
    expect(first_result.source_repository.runtime_root).to eq("/first")
    expect(second_result.source_repository.runtime_root).to eq("/second")
  end
end
