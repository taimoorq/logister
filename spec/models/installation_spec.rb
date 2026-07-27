# frozen_string_literal: true

require "rails_helper"

RSpec.describe Installation, type: :model do
  let(:installation) { described_class.current }

  it "accepts one active Ruby self-monitoring project and its active API key" do
    project = create(:project, :ruby)
    api_key = create(:api_key, project: project)

    installation.assign_attributes(self_monitoring_project: project, self_monitoring_api_key: api_key)

    expect(installation).to be_valid
  end

  it "rejects non-Ruby and archived self-monitoring projects" do
    non_ruby = create(:project, :python)
    installation.self_monitoring_project = non_ruby

    expect(installation).not_to be_valid
    expect(installation.errors[:self_monitoring_project]).to include("must use the Ruby integration")

    archived = create(:project, :ruby, :archived)
    installation.self_monitoring_project = archived

    expect(installation).not_to be_valid
    expect(installation.errors[:self_monitoring_project]).to include("must be active")
  end

  it "rejects a key from a different project" do
    project = create(:project, :ruby)
    other_key = create(:api_key, project: create(:project, :ruby))
    installation.assign_attributes(self_monitoring_project: project, self_monitoring_api_key: other_key)

    expect(installation).not_to be_valid
    expect(installation.errors[:self_monitoring_api_key]).to include("must belong to the self-monitoring project")
  end

  it "rejects an API key without a selected project" do
    installation.self_monitoring_api_key = create(:api_key)

    expect(installation).not_to be_valid
    expect(installation.errors[:self_monitoring_api_key]).to include("requires a self-monitoring project")
  end
end
