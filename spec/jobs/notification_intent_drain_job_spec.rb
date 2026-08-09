# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationIntentDrainJob, type: :job do
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs }

  it "enqueues the typed target and completes the durable intent" do
    intent = create(:notification_intent, available_at: 1.minute.ago)

    described_class.perform_now(intent.id)

    expect(ProjectErrorFirstOccurrenceAlertJob).to have_been_enqueued.with(intent.error_group_id)
    expect(intent.reload).to have_attributes(status: "enqueued", attempts: 1)
    expect(intent.enqueued_at).to be_present
  end

  it "releases the lease when the target enqueue fails" do
    now = Time.zone.parse("2026-08-08 12:00:00 UTC")
    intent = create(:notification_intent, available_at: now)
    allow(ProjectErrorFirstOccurrenceAlertJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "Redis unavailable")

    expect {
      described_class.new.perform(intent.id, now.iso8601)
    }.to raise_error(ActiveJob::EnqueueError, "Redis unavailable")

    expect(intent.reload.status).to eq("pending")
    expect(intent.last_error).to include("Redis unavailable")
    expect(intent.available_at).to be > now
  end

  it "recovers a committed intent that missed its immediate enqueue" do
    now = Time.zone.parse("2026-08-08 12:00:00 UTC")
    intent = create(:notification_intent, available_at: now)

    NotificationIntentSweepJob.perform_now(now.iso8601)

    expect(described_class).to have_been_enqueued.with(intent.id, now.iso8601)
  end
end
