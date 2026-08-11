# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectRetentionRunRecoverySweepJob, type: :job do
  include ActiveJob::TestHelper

  let(:now) { Time.zone.parse("2026-08-11 12:00:00") }

  before { clear_enqueued_jobs }

  it "fences a stale running attempt and reconstructs its lost queue work" do
    run = create(
      :project_retention_run,
      status: "running",
      attempt_token: SecureRandom.uuid,
      fence_version: 3,
      heartbeat_at: now - 16.minutes,
      available_at: nil
    )
    stale_token = run.attempt_token

    described_class.perform_now(now.iso8601(6))

    expect(run.reload).to have_attributes(
      status: "retrying",
      attempt_token: nil,
      fence_version: 4,
      recovery_enqueued_at: now
    )
    expect(run.metadata.dig("last_recovery", "fenced_attempt_token")).to eq(stale_token)
    expect(enqueued_run_ids).to eq([ run.id ])
  end

  it "leaves a fresh running attempt alone" do
    run = create(
      :project_retention_run,
      status: "running",
      attempt_token: SecureRandom.uuid,
      fence_version: 1,
      heartbeat_at: now - 14.minutes,
      available_at: nil
    )

    described_class.perform_now(now.iso8601(6))

    expect(run.reload.status).to eq("running")
    expect(enqueued_run_ids).to be_empty
  end

  it "enqueues a due retry once within the enqueue claim window" do
    run = create(:project_retention_run, status: "retrying", available_at: now - 1.second)

    described_class.perform_now(now.iso8601(6))
    described_class.perform_now((now + 1.minute).iso8601(6))

    expect(enqueued_run_ids).to eq([ run.id ])
  end

  def enqueued_run_ids
    enqueued_jobs.filter_map do |job|
      next unless job.fetch(:job) == ProjectRetentionJob

      job.fetch(:args).last.fetch("run_id")
    end
  end
end
