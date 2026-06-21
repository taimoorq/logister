# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectGithubIntegrationState, type: :model do
  def diagnostics(ready:, install_url: nil)
    instance_double(Github::ConfigurationDiagnostics::Result, ready?: ready, install_url: install_url)
  end

  it "shows linked installations and hides them from linkable installations" do
    project = create(:project, user: users(:one))
    linked_installation = create(:github_installation, installed_by: users(:one), account_login: "linked")
    linkable_installation = create(:github_installation, installed_by: users(:one), account_login: "linkable")
    create(:project_github_installation, project: project, github_installation: linked_installation)

    state = described_class.new(project: project, user: users(:one))

    expect(state.linked_installations).to contain_exactly(linked_installation)
    expect(state.linkable_installations).to contain_exactly(linkable_installation)
  end

  it "exposes active repositories from linked active installations only" do
    project = create(:project, user: users(:one))
    linked_installation = create(:github_installation, installed_by: users(:one))
    inactive_installation = create(:github_installation, installed_by: users(:one), active: false)
    active_repository = create(:github_repository, github_installation: linked_installation, full_name: "acme/active")
    create(:github_repository, github_installation: linked_installation, full_name: "acme/archived", archived: true)
    create(:github_repository, github_installation: inactive_installation, full_name: "acme/inactive-install")
    create(:github_repository, github_installation: create(:github_installation), full_name: "acme/unlinked")
    create(:project_github_installation, project: project, github_installation: linked_installation)
    create(:project_github_installation, project: project, github_installation: inactive_installation)

    state = described_class.new(project: project, user: users(:one))

    expect(state.available_repositories).to contain_exactly(active_repository)
  end

  it "removes already-connected repositories from the connectable list case-insensitively" do
    project = create(:project, user: users(:one))
    installation = create(:github_installation, installed_by: users(:one))
    connected_repository = create(:github_repository, github_installation: installation, full_name: "Acme/Private-API")
    connectable_repository = create(:github_repository, github_installation: installation, full_name: "acme/worker")
    create(:project_github_installation, project: project, github_installation: installation)
    create(:project_source_repository, project: project, full_name: "acme/private-api")

    state = described_class.new(project: project, user: users(:one))

    expect(state.available_repositories).to contain_exactly(connected_repository, connectable_repository)
    expect(state.connectable_repositories).to contain_exactly(connectable_repository)
  end

  it "reports a healthy app connection when configuration is ready and a linked installation is active" do
    project = create(:project, user: users(:one))
    installation = create(:github_installation, installed_by: users(:one))
    create(:project_github_installation, project: project, github_installation: installation)

    state = described_class.new(project: project, user: users(:one), app_diagnostics: diagnostics(ready: true))

    expect(state).to be_app_connection_healthy
    expect(state).not_to be_app_connection_needs_attention
    expect(state).not_to be_app_access_details_open
    expect(state.app_connection_label).to eq("GitHub connection healthy")
    expect(state.app_connection_message).to eq("Linked installations can sync repositories for this project.")
  end

  it "opens app access details when GitHub app configuration is incomplete" do
    project = create(:project, user: users(:one))
    installation = create(:github_installation, installed_by: users(:one))
    create(:project_github_installation, project: project, github_installation: installation)

    state = described_class.new(project: project, user: users(:one), app_diagnostics: diagnostics(ready: false))

    expect(state).not_to be_app_connection_healthy
    expect(state).to be_app_access_details_open
    expect(state.app_connection_label).to eq("GitHub connection needs setup")
    expect(state.app_connection_message).to eq("GitHub App configuration is incomplete.")
  end

  it "opens app access details when no active installation is linked" do
    project = create(:project, user: users(:one))
    create(:project_github_installation, project: project, github_installation: create(:github_installation, active: false))

    state = described_class.new(project: project, user: users(:one), app_diagnostics: diagnostics(ready: true))

    expect(state).to be_app_access_details_open
    expect(state.app_connection_message).to eq("Linked GitHub App installations are unavailable.")
  end

  it "opens app access details when no installation is linked to the project" do
    project = create(:project, user: users(:one))

    state = described_class.new(project: project, user: users(:one), app_diagnostics: diagnostics(ready: true))

    expect(state).to be_app_access_details_open
    expect(state.app_connection_message).to eq("No GitHub App installation is linked to this project.")
  end

  it "exposes install actions when the project has no linked GitHub App installation" do
    project = create(:project, user: users(:one))

    state = described_class.new(
      project: project,
      user: users(:one),
      app_diagnostics: diagnostics(ready: true, install_url: "https://github.com/apps/logister/installations/new")
    )

    actions = state.dashboard_actions
    expect(state.app_connection_status).to eq(:missing_installation)
    expect(state.app_connection_status_label).to eq("App not installed")
    expect(actions.first.label).to eq("Install GitHub App")
    expect(actions.first.target).to eq(:github_app_install_url)
    expect(actions.first).to be_external
    expect(actions.first).to be_primary
  end

  it "exposes setup actions when GitHub App configuration is incomplete" do
    project = create(:project, user: users(:one))

    state = described_class.new(project: project, user: users(:one), app_diagnostics: diagnostics(ready: false))

    expect(state.app_connection_status).to eq(:configuration_missing)
    expect(state.app_connection_tone).to eq(:danger)
    expect(state.dashboard_actions.map(&:target)).to eq([ :github_app_docs, :github_app_access ])
  end

  it "promotes repository connection when synced repositories are ready" do
    project = create(:project, user: users(:one))
    installation = create(:github_installation, installed_by: users(:one))
    create(:project_github_installation, project: project, github_installation: installation)
    create(:github_repository, github_installation: installation, full_name: "acme/private-api")

    state = described_class.new(project: project, user: users(:one), app_diagnostics: diagnostics(ready: true))

    expect(state.dashboard_actions.first.label).to eq("Connect repositories")
    expect(state.dashboard_actions.first.target).to eq(:available_source_repositories)
  end
end
