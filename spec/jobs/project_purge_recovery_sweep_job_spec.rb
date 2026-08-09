# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectPurgeRecoverySweepJob, type: :job do
  include ActiveJob::TestHelper

  let(:now) { Time.zone.parse("2026-08-08 12:00:00") }

  before { clear_enqueued_jobs }

  it "reconstructs a lost retry when an external step is due" do
    purge = create(:project_purge, status: "awaiting_external", current_step: "clickhouse")
    purge.steps.find_by!(store_name: "clickhouse").update!(
      status: "awaiting_external",
      result: { "retry_at" => (now - 1.second).iso8601(6) }
    )

    described_class.perform_now(now.iso8601(6))

    expect(enqueued_purge_ids).to eq([ purge.id ])
  end

  it "does not enqueue an external step before its durable retry time" do
    purge = create(:project_purge, status: "awaiting_external", current_step: "archives")
    purge.steps.find_by!(store_name: "archives").update!(
      status: "awaiting_external",
      result: { "retry_at" => (now + 1.minute).iso8601(6) }
    )

    described_class.perform_now(now.iso8601(6))

    expect(enqueued_purge_ids).to be_empty
  end

  it "recovers a stale running ledger but leaves a recently owned run alone" do
    stale = create(:project_purge, status: "running", updated_at: now - 11.minutes)
    create(:project_purge, status: "running", updated_at: now - 9.minutes)

    described_class.perform_now(now.iso8601(6))

    expect(enqueued_purge_ids).to eq([ stale.id ])
  end

  def enqueued_purge_ids
    enqueued_jobs.filter_map do |job|
      job.fetch(:args).first if job.fetch(:job) == ProjectPurgeJob
    end
  end
end
