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

    ProjectMonitorSweepJob.ensure_scheduled!(now, occurrences: 1)

    expect(enqueued_jobs.size).to eq(1)
    job = enqueued_jobs.first
    expect(job[:job]).to eq(ProjectMonitorSweepJob)
    expect(job[:args]).to eq([ run_at.utc.iso8601 ])
    expect(Time.zone.at(job[:at]).to_i).to eq(run_at.to_i)
  end

  it "does not enqueue a duplicate when the Redis schedule key already exists" do
    allow(ProjectHealthNotificationSweepJob).to receive(:sidekiq_recurring_redis_set_once).and_return(false)

    ProjectHealthNotificationSweepJob.ensure_scheduled!(Time.zone.parse("2026-06-20T12:10:30Z"), occurrences: 1)

    expect(enqueued_jobs).to be_empty
  end

  it "schedules daily retention for the next 2am UTC boundary" do
    now = Time.zone.parse("2026-06-20T02:00:00Z")
    run_at = Time.zone.parse("2026-06-21T02:00:00Z")
    allow(ProjectRetentionSweepJob).to receive(:sidekiq_recurring_redis_set_once).and_return(true)

    ProjectRetentionSweepJob.ensure_scheduled!(now, occurrences: 1)

    expect(enqueued_jobs.size).to eq(1)
    job = enqueued_jobs.first
    expect(job[:job]).to eq(ProjectRetentionSweepJob)
    expect(job[:args]).to eq([])
    expect(Time.zone.at(job[:at]).to_i).to eq(run_at.to_i)
  end

  it "seeds multiple future executions so one hard-stopped job cannot break the chain" do
    now = Time.zone.parse("2026-06-20T12:10:30Z")
    allow(ProjectMonitorSweepJob).to receive(:sidekiq_recurring_redis_set_once).and_return(true)

    ProjectMonitorSweepJob.ensure_scheduled!(now, occurrences: 3)

    expect(enqueued_jobs.filter { |job| job[:job] == ProjectMonitorSweepJob }.size).to eq(3)
    expect(enqueued_jobs.map { |job| Time.zone.at(job[:at]).strftime("%H:%M") }).to eq(%w[12:15 12:30 12:45])
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

  it "releases its schedule marker and stops the lookahead when enqueueing fails" do
    now = Time.zone.parse("2026-06-20T12:10:30Z")
    run_at = Time.zone.parse("2026-06-20T12:15:00Z")
    schedule_key = ProjectMonitorSweepJob.sidekiq_recurring_schedule_key(run_at)
    configured_job = double("configured recurring job")

    allow(SecureRandom).to receive(:uuid).and_return("owned-schedule-marker")
    allow(ProjectMonitorSweepJob).to receive(:sidekiq_recurring_redis_set_once).and_return(true)
    allow(ProjectMonitorSweepJob).to receive(:sidekiq_recurring_release_marker)
    allow(ProjectMonitorSweepJob).to receive(:set).and_return(configured_job)
    allow(configured_job).to receive(:perform_later).and_return(false)

    ProjectMonitorSweepJob.ensure_scheduled!(now, occurrences: 3)

    expect(ProjectMonitorSweepJob).to have_received(:sidekiq_recurring_redis_set_once).once.with(
      schedule_key,
      kind_of(Integer),
      value: "owned-schedule-marker"
    )
    expect(ProjectMonitorSweepJob).to have_received(:sidekiq_recurring_release_marker).once.with(
      schedule_key,
      "owned-schedule-marker"
    )
    expect(ProjectMonitorSweepJob).to have_received(:set).once.with(wait_until: run_at)
    expect(Logister).to have_received(:report_log).once.with(
      hash_including(
        message: "Sidekiq recurring job schedule failed",
        fingerprint: "logister:sidekiq_recurring:schedule_failed:project_monitor_sweep"
      )
    )
  end

  it "atomically releases only the schedule marker token it owns" do
    redis = double("Sidekiq Redis")
    schedule_key = "logister:sidekiq_recurring:scheduled:project_monitor_sweep:202606201215"

    allow(Sidekiq).to receive(:redis).and_yield(redis)
    expect(redis).to receive(:call).with(
      "EVAL",
      include("redis.call('get', KEYS[1]) == ARGV[1]"),
      1,
      schedule_key,
      "owned-schedule-marker"
    ).and_return(1)

    expect(
      ProjectMonitorSweepJob.sidekiq_recurring_release_marker(schedule_key, "owned-schedule-marker")
    ).to eq(1)
  end
end
