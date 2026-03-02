# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorGroup, type: :model do
  let(:project) { projects(:one) }
  let(:api_key) { api_keys(:one) }

  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:latest_event).class_name("IngestEvent").optional }
    it { is_expected.to have_many(:error_occurrences).dependent(:destroy) }
    it { is_expected.to have_many(:ingest_events).through(:error_occurrences) }
  end

  describe "scopes" do
    it "open returns unresolved" do
      group = create_error_group(project: project, api_key: api_key)
      expect(described_class.open).to include(group)
      group.mark_resolved!
      expect(described_class.open).not_to include(group)
    end
  end

  describe "lifecycle transitions" do
    it "mark_resolved! sets status and resolved_at" do
      group = create_error_group(project: project, api_key: api_key)
      group.mark_resolved!
      expect(group.reload).to be_resolved
      expect(group.resolved_at).to be_present
    end

    it "ignore! sets status and ignored_at" do
      group = create_error_group(project: project, api_key: api_key)
      group.ignore!
      expect(group.reload).to be_ignored
      expect(group.ignored_at).to be_present
    end

    it "archive! sets status and archived_at" do
      group = create_error_group(project: project, api_key: api_key)
      group.archive!
      expect(group.reload).to be_archived
    end

    it "reopen! clears resolved/ignored/archived and increments reopen_count" do
      group = create_error_group(project: project, api_key: api_key)
      group.mark_resolved!
      group.reopen!
      group.reload
      expect(group).to be_unresolved
      expect(group.resolved_at).to be_nil
      expect(group.reopen_count).to eq(1)
    end
  end

  describe "#trend" do
    it "returns array of daily occurrence counts for the last N days" do
      group = create_error_group(project: project, api_key: api_key)
      trend = group.trend(days: 7)
      expect(trend).to be_an(Array)
      expect(trend.size).to eq(7)
      expect(trend).to all(be_a(Integer))
    end
  end

  def create_error_group(project:, api_key:)
    event = IngestEvent.create!(
      project: project,
      api_key: api_key,
      event_type: :error,
      level: "error",
      message: "Test error",
      fingerprint: "spec-fp-#{SecureRandom.hex(4)}",
      occurred_at: Time.current
    )
    ErrorGroupingService.call(event)
    event.reload.error_group
  end
end
