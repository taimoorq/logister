# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectGithubIntegrationState, type: :model do
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
end
