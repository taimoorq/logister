# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectCapabilitySnapshot do
  it "reports unsupported capabilities without querying dynamic evidence for server projects" do
    project = build(:project, :ruby)
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      queries << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end

    snapshot = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      snapshot = described_class.for(project)
    end

    expect(snapshot.status(:symbol_artifacts).state).to eq(:unsupported)
    expect(snapshot.status(:symbol_artifacts)).to be_frozen
    expect(queries).to be_empty
  end

  it "separates Android product support from current project configuration" do
    project = create(:project, :android)
    create(:android_mapping_file, project: project)
    create(
      :project_integration_setting,
      project: project,
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.shop",
      credential_reference: "GOOGLE_PLAY_SERVICE_ACCOUNT"
    )

    snapshot = described_class.for(project)

    expect(snapshot.status(:mobile).state).to eq(:available)
    expect(snapshot.status(:session_health).state).to eq(:unconfigured)
    expect(snapshot.status(:stack_mapping).state).to eq(:partial)
    expect(snapshot.status(:distribution_store).state).to eq(:partial)
    expect(snapshot.status(:distribution_store).reason).to include("no report has been imported")
    expect(snapshot.statuses).to be_frozen
  end

  it "reports observed iOS correlation, verified symbols, and configured store access independently" do
    project = create(:project, :ios)
    group = create(:error_group, project: project)
    create(:error_occurrence, error_group: group, session_hash: "session-pseudonym")
    create(:apple_symbol_artifact, project: project, status: "verified")
    create(
      :project_integration_setting,
      project: project,
      provider: "app_store_connect",
      enabled: true,
      account_id: "issuer-id",
      external_project_id: "123456789",
      external_project_name: "Acme Shop",
      credential_reference: "APP_STORE_CONNECT_KEY"
    )

    snapshot = described_class.for(project)

    expect(snapshot.status(:session_health).state).to eq(:configured)
    expect(snapshot.status(:symbol_artifacts).state).to eq(:partial)
    expect(snapshot.status(:distribution_store).state).to eq(:partial)
  end

  it "rejects unregistered status states" do
    expect do
      CapabilityStatus.new(key: :mobile, state: :maybe, provenance: :test)
    end.to raise_error(ArgumentError, "Unknown capability state: maybe")
  end
end
