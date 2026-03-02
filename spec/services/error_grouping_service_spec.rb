# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorGroupingService, type: :model do
  let(:project) { projects(:one) }
  let(:api_key) { api_keys(:one) }

  describe ".call" do
    it "returns nil for metric events" do
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :metric,
        level: "info",
        message: "ping",
        occurred_at: Time.current
      )
      expect(described_class.call(event)).to be_nil
    end

    it "creates ErrorGroup and ErrorOccurrence for error event" do
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        level: "error",
        message: "NoMethodError: undefined method",
        fingerprint: "spec-fp-123",
        context: { "exception" => { "class" => "NoMethodError" } },
        occurred_at: Time.current
      )
      group = described_class.call(event)
      expect(group).to be_a(ErrorGroup)
      expect(group.project_id).to eq(project.id)
      expect(group.fingerprint).to eq("spec-fp-123")
      expect(group.title).to include("NoMethodError")
      expect(group.subtitle).to eq("NoMethodError")
      expect(group).to be_unresolved
      expect(group.occurrence_count).to eq(1)

      expect(event.reload.error_group_id).to eq(group.id)
      expect(ErrorOccurrence.exists?(error_group: group, ingest_event: event)).to be true
    end

    it "groups second event with same fingerprint into same ErrorGroup" do
      event1 = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "First",
        fingerprint: "same-fp",
        occurred_at: 1.hour.ago
      )
      group1 = described_class.call(event1)
      event2 = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "Second",
        fingerprint: "same-fp",
        occurred_at: Time.current
      )
      group2 = described_class.call(event2)
      expect(group2.id).to eq(group1.id)
      expect(group2.reload.occurrence_count).to eq(2)
      expect(ErrorOccurrence.where(error_group: group2).count).to eq(2)
    end

    it "derives fingerprint from first line of message when fingerprint blank" do
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "UniqueMessageLine123",
        fingerprint: nil,
        occurred_at: Time.current
      )
      group = described_class.call(event)
      expect(group.fingerprint).to eq("UniqueMessageLine123")
    end
  end
end
