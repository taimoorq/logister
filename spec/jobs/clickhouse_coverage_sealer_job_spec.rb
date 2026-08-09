# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClickhouseCoverageSealerJob, type: :job do
  it "seals only recently active projects and closes the shared client" do
    closed_at = Time.utc(2026, 8, 8, 12)
    active_project = create(:project)
    create(:project)
    create(:ingest_event, :metric, project: active_project, occurred_at: closed_at - 30.minutes)
    client = instance_double(Logister::ClickhouseClient, close: nil)
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
    allow(Logister::ClickhouseRecentCoverageSealer).to receive(:call)
    job = described_class.new
    allow(job).to receive(:reschedule_sidekiq_recurring_job)

    job.perform(0, closed_at.iso8601)

    expect(Logister::ClickhouseRecentCoverageSealer).to have_received(:call).once.with(
      project_id: active_project.id,
      client: client,
      closed_before: closed_at
    )
    expect(client).to have_received(:close).once
  end
end
