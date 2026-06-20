# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorGroupingService, type: :model do
  include ActiveJob::TestHelper

  let(:project) { projects(:one) }
  let(:api_key) { api_keys(:one) }

  before { clear_enqueued_jobs }

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
      expect(group.latest_event_id).to eq(event.id)
      expect(group.latest_event_occurred_at).to be_within(1.second).of(event.occurred_at)

      expect(event.reload.error_group_id).to eq(group.id)
      occurrence = ErrorOccurrence.find_by!(error_group: group, ingest_event: event)
      expect(occurrence.ingest_event_occurred_at).to be_within(1.second).of(event.occurred_at)
      expect(ProjectErrorFirstOccurrenceAlertJob).to have_been_enqueued.with(group.id)
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
      expect(group2.latest_event_id).to eq(event2.id)
      expect(group2.latest_event_occurred_at).to be_within(1.second).of(event2.occurred_at)
      expect(ErrorOccurrence.where(error_group: group2).count).to eq(2)
      expect(ProjectErrorGroupNotificationJob).to have_been_enqueued.with(group2.id, "frequent_error", hash_including("event_id" => event2.id))
    end

    it "enqueues a regression alert when a closed group receives a new occurrence" do
      group = create(:error_group, :resolved, project: project, fingerprint: "resolved-fp", occurrence_count: 1)
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "Resolved came back",
        fingerprint: "resolved-fp",
        occurred_at: Time.current
      )

      described_class.call(event)

      expect(group.reload).to be_unresolved
      expect(ProjectErrorGroupNotificationJob).to have_been_enqueued.with(group.id, "regression", hash_including("reopen_count" => 1))
    end

    it "enqueues milestone alerts at notable occurrence counts" do
      group = create(:error_group, project: project, fingerprint: "milestone-fp", occurrence_count: 9)
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "Milestone reached",
        fingerprint: "milestone-fp",
        occurred_at: Time.current
      )

      described_class.call(event)

      expect(ProjectErrorGroupNotificationJob).to have_been_enqueued.with(group.id, "error_milestone", hash_including("milestone" => 10))
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
