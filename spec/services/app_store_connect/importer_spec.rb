# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppStoreConnect::Importer do
  let(:project) { create(:project, :ios) }
  let(:setting) do
    create(
      :project_integration_setting,
      project: project,
      provider: "app_store_connect",
      enabled: true,
      external_project_id: "com.acme.shop",
      account_id: "issuer-123",
      external_project_name: "KEY123",
      credential_reference: "APP_STORE_CONNECT_PRIVATE_KEY"
    )
  end
  let(:client) do
    instance_double(
      AppStoreConnect::Client,
      app_for_bundle_id: { "id" => "apple-app-1", "attributes" => { "bundleId" => "com.acme.shop", "name" => "Acme Shop" } },
      performance_metrics: { "productData" => [ { "metricCategories" => [] } ] }
    )
  end

  it "stores a freshness-labelled store aggregate without merging SDK counts" do
    reporting = described_class.new(setting, client: client).call

    expect(reporting).to include("source" => "app_store_connect_power_performance", "scope" => "store_aggregate")
    expect(reporting.dig("app", "id")).to eq("apple-app-1")
    expect(reporting.fetch("freshness_note")).to include("days after release")
    expect(setting.reload.last_imported_at).to be_present
    expect(setting.metadata.dig("reporting", "metrics", "productData")).to be_present
  end

  it "records a bounded operator-visible failure" do
    allow(client).to receive(:app_for_bundle_id).and_raise(AppStoreConnect::Client::Error, "permission denied")

    expect { described_class.new(setting, client: client).call }.to raise_error(AppStoreConnect::Client::Error)
    expect(setting.reload.metadata.dig("last_error", "message")).to eq("permission denied")
    expect(setting.metadata["last_attempted_at"]).to be_present
  end
end
