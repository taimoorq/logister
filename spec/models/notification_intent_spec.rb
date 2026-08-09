# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationIntent, type: :model do
  it "captures one durable row for a logical notification" do
    group = create(:error_group)
    attributes = {
      project: group.project,
      kind: "first_occurrence",
      error_group: group,
      dedup_key: "error_group:#{group.id}:first_occurrence"
    }

    first = described_class.capture!(**attributes)
    second = described_class.capture!(**attributes)

    expect(second).to eq(first)
    expect(described_class.where(dedup_key: attributes[:dedup_key]).count).to eq(1)
  end

  it "uses a lease token to prevent a stale drainer from completing a reclaimed intent" do
    now = Time.zone.parse("2026-08-08 12:00:00 UTC")
    intent = create(:notification_intent, available_at: now)
    stale_token = intent.claim!(now: now)

    fresh_token = intent.claim!(now: now + described_class::PROCESSING_LEASE + 1.second)

    expect(fresh_token).to be_present
    expect(fresh_token).not_to eq(stale_token)
    expect(intent.mark_enqueued!(stale_token, now: now + 11.minutes)).to be false
    expect(intent.mark_enqueued!(fresh_token, now: now + 11.minutes)).to be true
    expect(intent.reload.status).to eq("enqueued")
  end

  it "rejects a subject from another project" do
    group = create(:error_group)
    intent = build(:notification_intent, project: create(:project), error_group: group)

    expect(intent).not_to be_valid
    expect(intent.errors[:error_group]).to include("must belong to the intent project")
  end
end
