# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorOccurrence, type: :model do
  let(:project) { projects(:one) }
  let(:api_key) { api_keys(:one) }

  def create_occurrence
    event = IngestEvent.create!(
      project: project,
      api_key: api_key,
      event_type: :error,
      message: "Occurrence spec",
      fingerprint: "occ-#{SecureRandom.hex(4)}",
      occurred_at: Time.current
    )
    ErrorGroupingService.call(event)
    event.reload.error_occurrence
  end

  describe "associations" do
    it "belongs to error_group" do
      expect(described_class.reflect_on_association(:error_group).macro).to eq(:belongs_to)
    end

    it "belongs to ingest_event" do
      expect(described_class.reflect_on_association(:ingest_event).macro).to eq(:belongs_to)
    end
  end

  describe "validations" do
    it "validates uniqueness of ingest_event_id scoped to error_group_id" do
      occ = create_occurrence
      dup = described_class.new(error_group: occ.error_group, ingest_event: occ.ingest_event, occurred_at: Time.current)
      expect(dup).not_to be_valid
      expect(dup.errors[:ingest_event_id]).to be_present
    end
  end

  describe "scopes" do
    it "recent_first orders by occurred_at desc" do
      occ = create_occurrence
      expect(described_class.recent_first).to eq(described_class.order(occurred_at: :desc))
    end
  end

  describe "callbacks" do
    it "syncs occurred_at from ingest_event when blank" do
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "Sync spec",
        fingerprint: "sync-#{SecureRandom.hex(4)}",
        occurred_at: 1.hour.ago
      )
      ErrorGroupingService.call(event)
      occ = event.reload.error_occurrence
      expect(occ.occurred_at).to be_within(1.second).of(event.occurred_at)
    end
  end

  describe "#to_param" do
    it "returns uuid" do
      occ = create_occurrence
      expect(occ.to_param).to eq(occ.uuid)
    end
  end
end
