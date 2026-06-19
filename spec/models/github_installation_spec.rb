# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubInstallation, type: :model do
  it "normalizes metadata fields" do
    installation = described_class.new(
      installation_id: 123,
      account_login: " acme ",
      account_type: " Organization ",
      repository_selection: " selected ",
      permissions: "bad",
      events: "bad"
    )

    expect(installation).to be_valid
    expect(installation.account_login).to eq("acme")
    expect(installation.permissions).to eq({})
    expect(installation.events).to eq([])
  end

  it "is unavailable when suspended" do
    installation = build(:github_installation, suspended_at: Time.current)

    expect(installation).not_to be_available
  end

  it "is visible only to the user who completed setup" do
    visible_installation = create(:github_installation, installed_by: users(:one))
    create(:github_installation, installed_by: users(:two))

    expect(described_class.visible_to(users(:one))).to contain_exactly(visible_installation)
  end

  it "links to projects through project GitHub installations" do
    installation = create(:github_installation)
    project = create(:project)
    create(:project_github_installation, project: project, github_installation: installation)

    expect(installation.projects).to contain_exactly(project)
  end

  it "summarizes active repositories and last sync time" do
    installation = create(:github_installation)
    synced_at = 5.minutes.ago
    latest_synced_at = 1.minute.ago
    create(:github_repository, github_installation: installation, last_synced_at: synced_at)
    create(:github_repository, github_installation: installation, active: false, last_synced_at: latest_synced_at)
    create(:github_repository, github_installation: installation, archived: true, last_synced_at: 2.minutes.ago)

    expect(installation.active_repository_count).to eq(1)
    expect(installation.last_repository_synced_at.to_i).to eq(latest_synced_at.to_i)
  end
end
