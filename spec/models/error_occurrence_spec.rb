# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorOccurrence, type: :model do
  let(:project) { projects(:one) }
  let(:api_key) { api_keys(:one) }

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
      occ = create(:error_occurrence, api_key: api_key, error_group: create(:error_group, project: project))
      dup = described_class.new(error_group: occ.error_group, ingest_event: occ.ingest_event, occurred_at: Time.current)
      expect(dup).not_to be_valid
      expect(dup.errors[:ingest_event_id]).to be_present
    end
  end

  describe "scopes" do
    it "recent_first orders by occurred_at desc" do
      occ = create(:error_occurrence, api_key: api_key, error_group: create(:error_group, project: project))
      expect(described_class.recent_first).to eq(described_class.order(occurred_at: :desc))
    end
  end

  describe "callbacks" do
    it "syncs occurred_at from ingest_event when blank" do
      group = create(:error_group, project: project)
      event = create(:ingest_event,
        project: project,
        api_key: api_key,
        fingerprint: group.fingerprint,
        message: "Sync spec",
        occurred_at: 1.hour.ago)
      occ = described_class.create!(error_group: group, ingest_event: event)

      expect(occ.occurred_at).to be_within(1.second).of(event.occurred_at)
    end
  end

  describe "#to_param" do
    it "returns uuid" do
      occ = create(:error_occurrence, api_key: api_key, error_group: create(:error_group, project: project))
      expect(occ.to_param).to eq(occ.uuid)
    end
  end

  describe "factory" do
    it "creates a coherent occurrence linked to its group and event" do
      occurrence = create(:error_occurrence, api_key: api_key, error_group: create(:error_group, project: project))

      expect(occurrence).to be_persisted
      expect(occurrence.error_group.project).to eq(project)
      expect(occurrence.ingest_event.project).to eq(project)
      expect(occurrence.ingest_event.error_group).to eq(occurrence.error_group)
    end
  end
end
