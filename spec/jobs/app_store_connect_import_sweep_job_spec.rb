# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppStoreConnectImportSweepJob, type: :job do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
    allow(described_class).to receive(:ensure_scheduled!)
  end

  it "enqueues configured iOS imports that have not succeeded recently" do
    due = create(
      :project_integration_setting,
      project: create(:project, :ios),
      provider: "app_store_connect",
      enabled: true,
      account_id: "issuer-123",
      external_project_id: "com.acme.shop",
      external_project_name: "KEY123",
      credential_reference: "APP_STORE_CONNECT_PRIVATE_KEY",
      last_imported_at: 30.minutes.ago
    )
    create(
      :project_integration_setting,
      project: create(:project, :ios),
      provider: "app_store_connect",
      enabled: true,
      account_id: "issuer-456",
      external_project_id: "com.acme.fresh",
      external_project_name: "KEY456",
      credential_reference: "APP_STORE_CONNECT_PRIVATE_KEY",
      last_imported_at: 5.minutes.ago
    )

    described_class.perform_now(Time.current.iso8601)

    expect(AppStoreConnectImportJob).to have_been_enqueued.with(due.id)
    expect(enqueued_jobs.count { |job| job[:job] == AppStoreConnectImportJob }).to eq(1)
  end

  it "does not enqueue disabled or incomplete settings" do
    create(
      :project_integration_setting,
      project: create(:project, :ios),
      provider: "app_store_connect",
      enabled: false,
      account_id: "issuer-123",
      external_project_id: "com.acme.shop",
      external_project_name: "KEY123",
      credential_reference: "APP_STORE_CONNECT_PRIVATE_KEY"
    )

    described_class.perform_now(Time.current.iso8601)

    expect(enqueued_jobs.none? { |job| job[:job] == AppStoreConnectImportJob }).to be(true)
  end
end
