# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectSourceRepository, type: :model do
  it "normalizes GitHub URLs to full names" do
    repository = build(:project_source_repository, full_name: " https://github.com/acme/storefront.git ")

    expect(repository).to be_valid
    expect(repository.full_name).to eq("acme/storefront")
    expect(repository.owner_name).to eq("acme")
    expect(repository.repo_name).to eq("storefront")
  end

  it "rejects unsafe source roots" do
    repository = build(:project_source_repository, source_root: "../secrets")

    expect(repository).not_to be_valid
    expect(repository.errors[:source_root]).to include("cannot include path traversal")
  end

  it "is configured only when enabled and backed by an available GitHub installation" do
    repository = build(:project_source_repository)

    expect(repository).to be_configured

    repository.github_installation.suspended_at = Time.current
    expect(repository).not_to be_configured
  end

  it "inherits repository metadata from a synced GitHub repository" do
    github_repository = create(
      :github_repository,
      full_name: "acme/storefront",
      default_branch: "trunk",
      external_id: 123_456
    )

    source_repository = build(
      :project_source_repository,
      github_repository: github_repository,
      github_installation: nil,
      external_id: nil,
      full_name: nil,
      default_branch: nil
    )

    expect(source_repository).to be_valid
    expect(source_repository.full_name).to eq("acme/storefront")
    expect(source_repository.default_branch).to eq("trunk")
    expect(source_repository.external_id).to eq(123_456)
    expect(source_repository.effective_github_installation).to eq(github_repository.github_installation)
  end
end
