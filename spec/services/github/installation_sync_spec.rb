# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::InstallationSync do
  let(:installation_payload) do
    {
      "id" => 123,
      "account" => { "login" => "acme", "type" => "Organization" },
      "repository_selection" => "selected",
      "permissions" => { "contents" => "read", "metadata" => "read" },
      "events" => %w[installation installation_repositories]
    }
  end

  let(:repository_payload) do
    {
      "id" => 456,
      "full_name" => "acme/storefront",
      "default_branch" => "main",
      "html_url" => "https://github.com/acme/storefront",
      "private" => true,
      "archived" => false,
      "permissions" => { "contents" => "read" }
    }
  end

  it "syncs an installation and repositories from the setup callback" do
    user = create(:user)
    app_client = instance_double(Github::AppClient, installation: installation_payload)
    repositories_client = instance_double(Github::InstallationRepositoriesClient, list: [ repository_payload ])

    result = described_class.new(app_client: app_client, repositories_client: repositories_client).from_setup(
      installation_id: "123",
      installed_by: user,
      state_verified: true
    )

    expect(result.status).to eq(:synced)
    expect(result.installation).to have_attributes(
      installation_id: 123,
      account_login: "acme",
      installed_by: user
    )
    expect(result.repositories.first).to have_attributes(
      external_id: 456,
      full_name: "acme/storefront",
      default_branch: "main"
    )
  end

  describe "setup ownership" do
    let(:app_client) { instance_double(Github::AppClient, installation: installation_payload) }
    let(:repositories_client) { instance_double(Github::InstallationRepositoriesClient, list: [ repository_payload ]) }
    let(:sync) { described_class.new(app_client: app_client, repositories_client: repositories_client) }

    it "refuses to reassign an installation owned by another user, even with a verified state" do
      owner = create(:user)
      installation = create(:github_installation, installation_id: 123, installed_by: owner)

      expect {
        sync.from_setup(installation_id: "123", installed_by: create(:user), state_verified: true)
      }.to raise_error(described_class::OwnershipError)

      expect(installation.reload.installed_by).to eq(owner)
      expect(app_client).not_to have_received(:installation)
    end

    it "requires a verified state to claim a new or webhook-created installation" do
      create(:github_installation, installation_id: 123, installed_by: nil)

      expect {
        sync.from_setup(installation_id: "123", installed_by: create(:user))
      }.to raise_error(described_class::OwnershipError)
    end

    it "claims an unowned installation with a verified state" do
      installation = create(:github_installation, installation_id: 123, installed_by: nil)
      user = create(:user)

      result = sync.from_setup(installation_id: "123", installed_by: user, state_verified: true)

      expect(result.installation).to eq(installation)
      expect(installation.reload.installed_by).to eq(user)
    end

    it "keeps the owner when webhooks update the installation" do
      owner = create(:user)
      installation = create(:github_installation, installation_id: 123, installed_by: owner)

      described_class.from_webhook(
        event: "installation",
        payload: { "action" => "new_permissions_accepted", "installation" => installation_payload, "repositories" => [ repository_payload ] },
        repositories_client: repositories_client
      )

      expect(installation.reload.installed_by).to eq(owner)
    end
  end

  it "marks removed repositories inactive and stores added repositories" do
    installation = create(:github_installation, installation_id: 123)
    removed_repository = create(:github_repository, github_installation: installation, external_id: 100)
    repositories_client = instance_double(Github::InstallationRepositoriesClient)

    result = described_class.from_webhook(
      event: "installation_repositories",
      payload: {
        "installation" => installation_payload,
        "repositories_removed" => [ { "id" => 100, "full_name" => "acme/old" } ],
        "repositories_added" => [ repository_payload ]
      },
      repositories_client: repositories_client
    )

    expect(result.status).to eq(:synced)
    expect(removed_repository.reload).not_to be_active
    expect(installation.github_repositories.find_by!(external_id: 456)).to be_active
  end

  it "deactivates installations and repositories when the app is deleted" do
    installation = create(:github_installation, installation_id: 123)
    repository = create(:github_repository, github_installation: installation)
    repositories_client = instance_double(Github::InstallationRepositoriesClient)

    result = described_class.from_webhook(
      event: "installation",
      payload: {
        "action" => "deleted",
        "installation" => installation_payload
      },
      repositories_client: repositories_client
    )

    expect(result.status).to eq(:deleted)
    expect(installation.reload).not_to be_active
    expect(installation.suspended_at).to be_present
    expect(repository.reload).not_to be_active
  end

  it "resyncs an existing installation by replacing repository state" do
    installation = create(:github_installation, installation_id: 123)
    stale_repository = create(:github_repository, github_installation: installation, external_id: 111, full_name: "acme/old")
    repositories_client = instance_double(Github::InstallationRepositoriesClient, list: [ repository_payload ])

    result = described_class.resync(installation: installation, repositories_client: repositories_client)

    expect(result.status).to eq(:synced)
    expect(result.repositories.first.full_name).to eq("acme/storefront")
    expect(stale_repository.reload).not_to be_active
  end

  it "deactivates all repositories when a resync returns no repositories" do
    installation = create(:github_installation, installation_id: 123)
    repository = create(:github_repository, github_installation: installation)
    repositories_client = instance_double(Github::InstallationRepositoriesClient, list: [])

    result = described_class.resync(installation: installation, repositories_client: repositories_client)

    expect(result.status).to eq(:synced)
    expect(result.repositories).to be_empty
    expect(repository.reload).not_to be_active
  end

  it "rejects resync for unavailable installations" do
    installation = build(:github_installation, active: false)
    repositories_client = instance_double(Github::InstallationRepositoriesClient)

    expect do
      described_class.resync(installation: installation, repositories_client: repositories_client)
    end.to raise_error(Github::InstallationSync::Error, "GitHub installation is unavailable")
  end
end
