# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckInMonitor, type: :model do
  include ActiveJob::TestHelper

  describe "factory" do
    it "builds a valid check-in monitor" do
      monitor = build(:check_in_monitor, project: projects(:one))

      expect(monitor).to be_valid
      expect(monitor.project).to eq(projects(:one))
    end

    it "creates a monitor with a matching last event" do
      monitor = create(:check_in_monitor, :with_last_event, project: projects(:one), api_key: api_keys(:one))

      expect(monitor).to be_persisted
      expect(monitor.last_event).to be_check_in
      expect(monitor.last_event.project).to eq(projects(:one))
      expect(monitor.last_event_occurred_at).to be_within(1.second).of(monitor.last_event.occurred_at)
    end
  end

  describe "#status" do
    it "returns missed when latest check-in exceeds interval + grace" do
      monitor = build(:check_in_monitor,
        project: projects(:one),
        slug: "nightly-job",
        expected_interval_seconds: 60,
        last_check_in_at: 2.minutes.ago,
        last_status: "ok")

      expect(monitor.status).to eq("missed")
    end

    it "returns error when last status is error" do
      monitor = build(:check_in_monitor,
        project: projects(:one),
        slug: "nightly-job",
        expected_interval_seconds: 60,
        last_check_in_at: Time.current,
        last_status: "error")

      expect(monitor.status).to eq("error")
    end

    it "returns paused and does not become missed while monitoring is paused" do
      monitor = build(:check_in_monitor,
        project: projects(:one),
        slug: "retired-job",
        expected_interval_seconds: 60,
        last_check_in_at: 1.day.ago,
        last_status: "ok",
        monitoring_paused_at: 1.hour.ago)

      expect(monitor.status).to eq("paused")
      expect(monitor.missed?).to be false
    end
  end

  describe ".record!" do
    let(:project) { create(:project) }
    let(:api_key) { create(:api_key, project: project, user: project.user) }
    let(:slug) { "nightly-import" }

    it "does not move monitor state backward when an older delivery is retried later" do
      newer = check_in_event(status: "ok", occurred_at: Time.zone.parse("2026-08-08 12:10:00 UTC"))
      older = check_in_event(status: "error", occurred_at: Time.zone.parse("2026-08-08 12:00:00 UTC"))

      monitor = described_class.record!(project: project, event: newer)
      described_class.record!(project: project, event: older)

      expect(monitor.reload).to have_attributes(
        last_event_id: newer.id,
        last_check_in_at: newer.occurred_at,
        last_status: "ok"
      )
      expect(enqueued_jobs).to be_empty
    end

    it "is idempotent when the same error observation is replayed" do
      event = check_in_event(status: "error", occurred_at: Time.zone.parse("2026-08-08 12:00:00 UTC"))

      expect {
        described_class.record!(project: project, event: event)
        described_class.record!(project: project, event: event)
      }.to change { enqueued_jobs.count }.by(1)

      expect(project.check_in_monitors.find_by!(slug: slug).last_event_id).to eq(event.id)
      expect(NotificationIntent.where(check_in_monitor: project.check_in_monitors.find_by!(slug: slug)).count).to eq(1)
    end

    it "keeps the transition intent durable when its immediate enqueue fails" do
      event = check_in_event(status: "error", occurred_at: Time.zone.parse("2026-08-08 12:00:00 UTC"))
      allow(NotificationIntentDrainJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "Redis unavailable")

      monitor = described_class.record!(project: project, event: event)

      intent = NotificationIntent.find_by!(check_in_monitor: monitor, kind: "monitor_missed")
      expect(intent.status).to eq("pending")
      expect(intent.metadata).to include(
        "transition_id" => monitor.notification_transition_id,
        "expected_status" => "error"
      )
    end

    it "rolls back an initial monitor transition when its intent cannot be persisted" do
      event = check_in_event(status: "error", occurred_at: Time.zone.parse("2026-08-08 12:00:00 UTC"))
      allow(NotificationIntent).to receive(:capture!).and_wrap_original do |original, *arguments, **keywords|
        original.call(*arguments, **keywords)
        raise ActiveRecord::StatementInvalid, "forced rollback"
      end

      expect {
        described_class.record!(project: project, event: event)
      }.to raise_error(ActiveRecord::StatementInvalid, "forced rollback")

      expect(project.check_in_monitors.where(slug: slug)).to be_empty
      expect(NotificationIntent.where(project: project)).to be_empty
    end

    def check_in_event(status:, occurred_at:)
      create(
        :ingest_event,
        :check_in,
        project: project,
        api_key: api_key,
        message: slug,
        occurred_at: occurred_at,
        context: {
          "check_in_slug" => slug,
          "check_in_status" => status,
          "expected_interval_seconds" => 300,
          "environment" => "production"
        }
      )
    end
  end
end
