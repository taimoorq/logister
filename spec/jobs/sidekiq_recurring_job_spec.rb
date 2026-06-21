# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sidekiq recurring jobs", type: :job do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
    allow(Logister).to receive(:report_log)
  end

  it "schedules interval jobs for the next quarter-hour boundary" do
    now = Time.zone.parse("2026-06-20T12:10:30Z")
    run_at = Time.zone.parse("2026-06-20T12:15:00Z")
    allow(ProjectMonitorSweepJob).to receive(:sidekiq_recurring_redis_set_once).and_return(true)

    ProjectMonitorSweepJob.ensure_scheduled!(now)

    expect(enqueued_jobs.size).to eq(1)
    job = enqueued_jobs.first
    expect(job[:job]).to eq(ProjectMonitorSweepJob)
    expect(job[:args]).to eq([ run_at.utc.iso8601 ])
    expect(Time.zone.at(job[:at]).to_i).to eq(run_at.to_i)
  end

  it "does not enqueue a duplicate when the Redis schedule key already exists" do
    allow(ProjectHealthNotificationSweepJob).to receive(:sidekiq_recurring_redis_set_once).and_return(false)

    ProjectHealthNotificationSweepJob.ensure_scheduled!(Time.zone.parse("2026-06-20T12:10:30Z"))

    expect(enqueued_jobs).to be_empty
  end

  it "schedules daily retention for the next 2am UTC boundary" do
    now = Time.zone.parse("2026-06-20T02:00:00Z")
    run_at = Time.zone.parse("2026-06-21T02:00:00Z")
    allow(ProjectRetentionSweepJob).to receive(:sidekiq_recurring_redis_set_once).and_return(true)

    ProjectRetentionSweepJob.ensure_scheduled!(now)

    expect(enqueued_jobs.size).to eq(1)
    job = enqueued_jobs.first
    expect(job[:job]).to eq(ProjectRetentionSweepJob)
    expect(job[:args]).to eq([])
    expect(Time.zone.at(job[:at]).to_i).to eq(run_at.to_i)
  end

  it "reports schedule enqueue failures" do
    allow(ProjectMonitorSweepJob).to receive(:sidekiq_recurring_redis_set_once).and_raise(Redis::BaseError, "redis unavailable")

    ProjectMonitorSweepJob.ensure_scheduled!(Time.zone.parse("2026-06-20T12:10:30Z"))

    expect(Logister).to have_received(:report_log).with(
      hash_including(
        message: "Sidekiq recurring job schedule failed",
        level: "error",
        fingerprint: "logister:sidekiq_recurring:schedule_failed:project_monitor_sweep"
      )
    )
  end
end
