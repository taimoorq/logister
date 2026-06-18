# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubRepository, type: :model do
  it "normalizes repository identity fields" do
    repository = build(:github_repository, full_name: " acme/storefront.git ")

    expect(repository).to be_valid
    expect(repository.full_name).to eq("acme/storefront")
    expect(repository.owner_name).to eq("acme")
    expect(repository.repo_name).to eq("storefront")
  end

  it "is visible only to the user who completed the installation" do
    installation = create(:github_installation, installed_by: users(:one))
    visible_repository = create(:github_repository, github_installation: installation)
    create(:github_repository, github_installation: create(:github_installation, installed_by: users(:two)))

    expect(described_class.visible_to(users(:one))).to contain_exactly(visible_repository)
  end

  it "is unavailable when archived" do
    repository = build(:github_repository, archived: true)

    expect(repository).not_to be_available
  end
end
