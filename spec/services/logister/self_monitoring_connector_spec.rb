# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::SelfMonitoringConnector, type: :model do
  let(:admin) { create(:user, application_admin: true) }
  let(:project) { create(:project, :ruby, user: admin) }
  let(:installation) { Installation.current }

  before do
    allow(InstanceConfiguration::Runtime).to receive(:apply!)
  end

  it "links the installation, creates a dedicated token, and saves the local endpoint" do
    result = described_class.call(project: project, actor: admin, installation: installation)

    installation.reload
    expect(result.status).to be_connected
    expect(result.created_api_key).to be(true)
    expect(installation.self_monitoring_project).to eq(project)
    expect(installation.self_monitoring_api_key).to have_attributes(
      project: project,
      name: described_class::API_KEY_NAME,
      revoked_at: nil
    )
    expect(ApiKey.authenticate(InstanceConfiguration.value("observability.api_key"))).to eq(installation.self_monitoring_api_key)
    expect(InstanceConfiguration.value("observability.endpoint")).to eq(result.status.local_ingest_endpoint)
    expect(InstanceConfiguration::Runtime).to have_received(:apply!)
  end

  it "does not rotate a connection that is already valid" do
    first = described_class.call(project: project, actor: admin, installation: installation)

    expect {
      second = described_class.call(project: project, actor: admin, installation: installation.reload)
      expect(second.created_api_key).to be(false)
    }.not_to change(ApiKey, :count)

    expect(first.status).to be_connected
  end

  it "rotates only the previously associated dedicated key when changing projects" do
    first = described_class.call(project: project, actor: admin, installation: installation)
    old_key = installation.reload.self_monitoring_api_key
    next_project = create(:project, :ruby, user: admin)

    result = described_class.call(project: next_project, actor: admin, installation: installation)

    expect(result.status).to be_connected
    expect(installation.reload.self_monitoring_project).to eq(next_project)
    expect(old_key.reload).not_to be_active
    expect(first.status.project).to eq(project)
  end

  it "keeps environment-managed credentials authoritative and reports a mismatch" do
    original_api_key = ENV["LOGISTER_API_KEY"]
    original_endpoint = ENV["LOGISTER_ENDPOINT"]
    ENV["LOGISTER_API_KEY"] = "not-this-project"
    ENV["LOGISTER_ENDPOINT"] = "https://remote.example/api/v1/ingest_events"

    expect {
      result = described_class.call(project: project, actor: admin, installation: installation)
      expect(result.status).not_to be_connected
      expect(result.status.environment_override_keys).to contain_exactly("LOGISTER_API_KEY", "LOGISTER_ENDPOINT")
    }.not_to change(ApiKey, :count)

    expect(installation.reload.self_monitoring_project).to eq(project)
    expect(installation.self_monitoring_api_key).to be_nil
  ensure
    ENV["LOGISTER_API_KEY"] = original_api_key
    ENV["LOGISTER_ENDPOINT"] = original_endpoint
  end

  it "requires an application administrator and an active Ruby project" do
    expect {
      described_class.call(project: project, actor: create(:user), installation: installation)
    }.to raise_error(ArgumentError, "An application administrator is required")

    expect {
      described_class.call(project: create(:project, :python, user: admin), actor: admin, installation: installation)
    }.to raise_error(ArgumentError, "Self-monitoring requires an active Ruby project")
  end
end
