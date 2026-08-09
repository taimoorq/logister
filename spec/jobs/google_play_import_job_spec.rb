# frozen_string_literal: true

require "rails_helper"

RSpec.describe GooglePlayImportJob, type: :job do
  include ActiveJob::TestHelper

  let(:setting) do
    create(
      :project_integration_setting,
      project: create(:project, :android),
      provider: "google_play",
      enabled: true,
      external_project_id: "com.acme.shop",
      credential_reference: "GOOGLE_PLAY_REPORTING_CREDENTIALS"
    )
  end

  before { clear_enqueued_jobs }

  it "retries a classified transient failure without releasing the live schedule lease" do
    token = setting.claim_import_schedule!
    error = GooglePlay::DeveloperReportingClient::Error.new(
      "quota reached",
      classification: "rate_limit",
      retryable: true,
      retry_after: 90
    )
    importer = instance_double(GooglePlay::Importer)
    allow(GooglePlay::Importer).to receive(:new).with(setting).and_return(importer)
    allow(importer).to receive(:call).and_raise(error)

    described_class.perform_now(setting.id, token)

    retry_entry = enqueued_jobs.find { |entry| entry[:job] == described_class }
    expect(retry_entry).to be_present
    expect(retry_entry[:at]).to be_within(2.seconds).of(90.seconds.from_now.to_f)
    schedule = setting.reload.metadata.fetch("import_schedule")
    expect(schedule["token"]).to eq(token)
    expect(Time.zone.parse(schedule.fetch("expires_at"))).to be > 94.seconds.from_now
  end

  it "releases the schedule lease after a terminal credential failure" do
    token = setting.claim_import_schedule!
    error = GooglePlay::DeveloperReportingClient::Error.new(
      "credentials rejected",
      classification: "credentials",
      retryable: false
    )
    importer = instance_double(GooglePlay::Importer)
    allow(GooglePlay::Importer).to receive(:new).with(setting).and_return(importer)
    allow(importer).to receive(:call).and_raise(error)

    expect { described_class.perform_now(setting.id, token) }.to raise_error(error)
    expect(setting.reload.metadata["import_schedule"]).to be_nil
  end
end
