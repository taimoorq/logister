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

  it "releases its schedule marker and stops the lookahead when enqueueing fails" do
    now = Time.zone.parse("2026-05-21T00:00:00Z")
    run_at = Time.zone.parse("2026-05-21T01:02:00Z")
    schedule_key = described_class.schedule_key(run_at)
    configured_job = double("configured digest scheduler job")

    allow(SecureRandom).to receive(:uuid).and_return("owned-schedule-marker")
    allow(described_class).to receive(:release_schedule_marker)
    allow(described_class).to receive(:set).and_return(configured_job)
    allow(configured_job).to receive(:perform_later).and_raise(StandardError, "enqueue unavailable")

    described_class.ensure_scheduled!(now, occurrences: 3)

    expect(described_class).to have_received(:redis_set_once).once.with(
      schedule_key,
      kind_of(Integer),
      value: "owned-schedule-marker"
    )
    expect(described_class).to have_received(:release_schedule_marker).once.with(
      schedule_key,
      "owned-schedule-marker"
    )
    expect(described_class).to have_received(:set).once.with(wait_until: run_at)
    expect(Logister).to have_received(:report_log).once.with(
      hash_including(
        message: "Error digest scheduler enqueue failed",
        fingerprint: "logister:error_digest_scheduler:schedule_failed"
      )
    )
  end

  it "atomically releases only the schedule marker token it owns" do
    redis = double("Sidekiq Redis")
    schedule_key = "logister:error_digest_scheduler:scheduled:2026052101"

    allow(Sidekiq).to receive(:redis).and_yield(redis)
    expect(redis).to receive(:call).with(
      "EVAL",
      include("redis.call('get', KEYS[1]) == ARGV[1]"),
      1,
      schedule_key,
      "owned-schedule-marker"
    ).and_return(1)

    expect(described_class.release_schedule_marker(schedule_key, "owned-schedule-marker")).to eq(1)
  end
end
