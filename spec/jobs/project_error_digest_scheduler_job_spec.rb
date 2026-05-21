# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectErrorDigestSchedulerJob, type: :job do
  before do
    allow(described_class).to receive(:redis_set_once).and_return(true)
    allow(Logister).to receive(:report_check_in)
    allow(Logister).to receive(:report_log)
  end

  it "reports a scheduler check-in with the queued digest count" do
    job = described_class.new
    allow(described_class).to receive(:ensure_scheduled!)
    allow(job).to receive(:enqueue_due_digests).and_return(2)

    job.perform("2026-05-21T00:00:00Z")

    expect(Logister).to have_received(:report_check_in).with(
      hash_including(
        slug: "logister.error_digest_scheduler",
        status: "ok",
        expected_interval_seconds: 3900,
        context: hash_including(
          scheduler: hash_including(
            name: "logister.error_digest_scheduler",
            ran_at: "2026-05-21T00:00:00Z",
            queued_digests: 2
          )
        )
      )
    )
  end

  it "reports scheduler failures before reraising" do
    job = described_class.new
    allow(described_class).to receive(:ensure_scheduled!)
    allow(job).to receive(:enqueue_due_digests).and_raise(RuntimeError, "scheduler failed")

    expect {
      job.perform("2026-05-21T00:00:00Z")
    }.to raise_error(RuntimeError, "scheduler failed")

    expect(Logister).to have_received(:report_check_in).with(
      hash_including(
        slug: "logister.error_digest_scheduler",
        status: "error",
        expected_interval_seconds: 3900
      )
    )
    expect(Logister).to have_received(:report_log).with(
      hash_including(
        message: "Error digest scheduler failed",
        level: "error",
        fingerprint: "logister:error_digest_scheduler:failure"
      )
    )
  end

  it "reports enqueue scheduling failures from ensure_scheduled" do
    allow(described_class).to receive(:redis_set_once).and_raise(Redis::BaseError, "redis unavailable")

    described_class.ensure_scheduled!(Time.zone.parse("2026-05-21T00:00:00Z"))

    expect(Logister).to have_received(:report_log).with(
      hash_including(
        message: "Error digest scheduler enqueue failed",
        level: "error",
        fingerprint: "logister:error_digest_scheduler:schedule_failed"
      )
    )
  end
end
