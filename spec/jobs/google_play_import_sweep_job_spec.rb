# frozen_string_literal: true

require "rails_helper"

RSpec.describe GooglePlayImportSweepJob, type: :job do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
    allow(described_class).to receive(:ensure_scheduled!)
  end

  it "leases and enqueues only due configured active Android imports" do
    due = create(
      :project_integration_setting,
      project: create(:project, :android),
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.shop",
      credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS",
      last_imported_at: 30.minutes.ago
    )
    create(
      :project_integration_setting,
      project: create(:project, :android),
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.fresh",
      credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS",
      last_imported_at: 5.minutes.ago
    )
    archived = create(:project, :android, archived_at: 1.hour.ago)
    create(
      :project_integration_setting,
      project: archived,
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.archived",
      credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS"
    )

    described_class.perform_now(Time.current.iso8601)

    job = enqueued_jobs.find { |entry| entry[:job] == GooglePlayImportJob }
    expect(job).to be_present
    expect(job[:args].first).to eq(due.id)
    expect(job[:args].second).to eq(due.reload.metadata.dig("import_schedule", "token"))
    expect(enqueued_jobs.count { |entry| entry[:job] == GooglePlayImportJob }).to eq(1)
  end

  it "does not enqueue a second import while the first schedule lease is live" do
    setting = create(
      :project_integration_setting,
      project: create(:project, :android),
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.shop",
      credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS"
    )
    setting.claim_import_schedule!(now: Time.current)

    described_class.perform_now(Time.current.iso8601)

    expect(enqueued_jobs.none? { |entry| entry[:job] == GooglePlayImportJob }).to be(true)
  end
end
