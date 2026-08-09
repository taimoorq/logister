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
      intent = NotificationIntent.find_by!(kind: "first_occurrence", error_group: group)
      expect(NotificationIntentDrainJob).to have_been_enqueued.with(intent.id)
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
      evaluation = NotificationEvaluation.find_by!(kind: "frequent_error", error_group: group2)
      expect(evaluation.bucket).to eq(event2.occurred_at.utc.strftime("%Y%m%d%H"))
      expect(FrequentErrorNotificationEvaluationJob).to have_been_enqueued.with(evaluation.id)
    end

    it "does not double-count when the same event is grouped again" do
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "Same event",
        fingerprint: "same-event-fp",
        occurred_at: Time.current
      )

      group = described_class.call(event)
      clear_enqueued_jobs

      expect(described_class.call(event.reload).id).to eq(group.id)
      expect(group.reload.occurrence_count).to eq(1)
      expect(ErrorOccurrence.where(error_group: group, ingest_event: event).count).to eq(1)
      expect(NotificationIntentDrainJob).not_to have_been_enqueued
    end

    it "retries duplicate occurrence races without leaving partial group state" do
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "Duplicate race",
        fingerprint: "duplicate-race-fp",
        occurred_at: Time.current
      )
      attempts = 0

      allow(ErrorOccurrence).to receive(:create!).and_wrap_original do |original, *args, **kwargs, &block|
        attempts += 1
        raise ActiveRecord::RecordNotUnique, "duplicate occurrence" if attempts == 1

        original.call(*args, **kwargs, &block)
      end

      group = described_class.call(event)

      expect(attempts).to eq(2)
      expect(ErrorGroup.where(project: project, fingerprint: "duplicate-race-fp").count).to eq(1)
      expect(group.reload.occurrence_count).to eq(1)
      expect(event.reload.error_group_id).to eq(group.id)
      expect(ErrorOccurrence.where(error_group: group, ingest_event: event).count).to eq(1)
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
      intent = NotificationIntent.find_by!(kind: "regression", error_group: group)
      expect(intent.metadata).to include("reopen_count" => 1)
      NotificationIntentDrainJob.perform_now(intent.id)
      expect(ProjectErrorGroupNotificationJob).to have_been_enqueued.with(group.id, "regression", hash_including("reopen_count" => 1))
    end

    it "records historical evidence received after resolution without reopening or alerting" do
      closure_time = 1.day.ago
      group = create(
        :error_group,
        :resolved,
        project: project,
        fingerprint: "historical-resolved-fp",
        occurrence_count: 1,
        resolved_at: closure_time,
        first_seen_at: 3.days.ago,
        last_seen_at: 3.days.ago,
        latest_event_occurred_at: 3.days.ago
      )
      historical_time = 2.days.ago
      normalized = TelemetryEvidenceNormalizer.normalize(
        context: { "platform" => "ios", "diagnostic" => { "source" => "metrickit", "kind" => "crash" } },
        client_occurred_at: historical_time,
        received_at: Time.current
      )
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "Historical crash arrived late",
        fingerprint: "historical-resolved-fp",
        occurred_at: historical_time,
        context: normalized.context
      )

      described_class.call(event)

      expect(group.reload).to be_resolved
      expect(group.occurrence_count).to eq(2)
      expect(group.regression_count).to eq(0)
      expect(NotificationIntent.where(kind: "regression", error_group: group)).to be_empty
      expect(NotificationEvaluation.where(kind: "frequent_error", error_group: group)).to be_empty
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

      intent = NotificationIntent.find_by!(kind: "error_milestone", error_group: group)
      expect(intent.metadata).to include("milestone" => 10)
      NotificationIntentDrainJob.perform_now(intent.id)
      expect(ProjectErrorGroupNotificationJob).to have_been_enqueued.with(group.id, "error_milestone", hash_including("milestone" => 10))
    end

    it "commits frequent-error evaluation observations with the grouping mutation" do
      create(:error_group, :resolved, project: project, fingerprint: "transaction-fp", occurrence_count: 1)
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "Transactional evaluation",
        fingerprint: "transaction-fp",
        occurred_at: Time.current
      )
      allow(NotificationEvaluation).to receive(:observe_frequent_error!).and_wrap_original do |original, *arguments, **keywords|
        original.call(*arguments, **keywords)
        raise ActiveRecord::StatementInvalid, "forced rollback"
      end

      expect { described_class.call(event) }.to raise_error(ActiveRecord::StatementInvalid, "forced rollback")

      expect(NotificationEvaluation.where(error_group: project.error_groups.find_by!(fingerprint: "transaction-fp"))).to be_empty
      expect(NotificationIntent.where(project: project)).to be_empty
    end

    it "keeps a committed intent pending when the immediate Sidekiq handoff fails" do
      event = IngestEvent.create!(
        project: project,
        api_key: api_key,
        event_type: :error,
        message: "Durable notification",
        fingerprint: "durable-notification-fp",
        occurred_at: Time.current
      )
      allow(NotificationIntentDrainJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "Redis unavailable")

      group = described_class.call(event)

      expect(NotificationIntent.find_by!(error_group: group, kind: "first_occurrence").status).to eq("pending")
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

    it "groups Android failures by mechanism, root type, and stable in-app failure point" do
      android_project = create(:project, :android)
      android_key = create(:api_key, project: android_project, user: android_project.user)
      base_context = JSON.parse(Rails.root.join("spec/fixtures/files/android_error_payload.json").read).fetch("context")
      first = create(:ingest_event, project: android_project, api_key: android_key, message: "Checkout 123 failed", context: base_context)
      changed_context = base_context.deep_dup
      changed_context["exception"]["message"] = "Checkout 987 failed"
      changed_context["exception"]["stacktrace"][0]["line"] = 101
      second = create(:ingest_event, project: android_project, api_key: android_key, message: "Checkout 987 failed", context: changed_context)

      first_group = described_class.call(first)
      second_group = described_class.call(second)

      expect(second_group).to eq(first_group)
      expect(first_group.reload.occurrence_count).to eq(2)
      expect(first_group.grouping_algorithm_version).to eq(AndroidErrorGroupingEvidence::VERSION)
      expect(first_group.grouping_evidence).to include(
        "mechanism" => "handled_exception",
        "root_exception_type" => "java.io.IOException",
        "top_in_app_class" => "com.acme.shop.storage.CartStore",
        "top_in_app_method" => "write"
      )
    end

    it "keeps different Android in-app failure points in separate groups" do
      android_project = create(:project, :android)
      android_key = create(:api_key, project: android_project, user: android_project.user)
      context = JSON.parse(Rails.root.join("spec/fixtures/files/android_error_payload.json").read).fetch("context")
      first = create(:ingest_event, project: android_project, api_key: android_key, message: "Same dynamic message", context: context)
      changed = context.deep_dup
      changed["exception"]["cause"]["stacktrace"][0]["method"] = "replace"
      second = create(:ingest_event, project: android_project, api_key: android_key, message: "Same dynamic message", context: changed)

      expect(described_class.call(first)).not_to eq(described_class.call(second))
    end

    it "groups iOS reports by stable application symbols instead of dynamic messages and line data" do
      ios_project = create(:project, :ios)
      ios_key = create(:api_key, project: ios_project, user: ios_project.user)
      context = JSON.parse(Rails.root.join("spec/fixtures/files/ios_error_payload.json").read).fetch("context")
      first = create(:ingest_event, project: ios_project, api_key: ios_key, message: "Order 123 failed", context: context)
      changed = context.deep_dup
      changed["exception"]["message"] = "Order 987 failed"
      changed["exception"]["threads"][0]["frames"][0]["line"] = 999
      changed["exception"]["threads"][0]["frames"][0]["symbol"] = "CheckoutViewModel.submit(_:) + 140"
      second = create(:ingest_event, project: ios_project, api_key: ios_key, message: "Order 987 failed", context: changed)

      first_group = described_class.call(first)
      second_group = described_class.call(second)

      expect(second_group).to eq(first_group)
      expect(first_group.reload.grouping_algorithm_version).to eq(IosErrorGroupingEvidence::VERSION)
      expect(first_group.grouping_evidence).to include(
        "mechanism" => "handled_exception",
        "exception_type" => "CheckoutError",
        "top_in_app_symbol" => "CheckoutViewModel.submit(_:)"
      )
    end

    it "keeps an iOS group stable when matching UUID-relative frames gain symbols" do
      ios_project = create(:project, :ios)
      ios_key = create(:api_key, project: ios_project, user: ios_project.user)
      context = JSON.parse(Rails.root.join("spec/fixtures/files/ios_error_payload.json").read).fetch("context")
      frame = context["exception"]["threads"][0]["frames"][0]
      frame.merge!("image_uuid" => "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", "relative_address" => "0x1290")
      frame.delete("symbol")
      first = create(:ingest_event, project: ios_project, api_key: ios_key, message: "Unresolved frame", context: context)
      enriched = context.deep_dup
      enriched["exception"]["threads"][0]["frames"][0]["symbol"] = "CheckoutViewModel.submit(_:)"
      second = create(:ingest_event, project: ios_project, api_key: ios_key, message: "Symbolicated frame", context: enriched)

      expect(described_class.call(second)).to eq(described_class.call(first))
    end

    it "materializes mobile occurrence impact dimensions idempotently" do
      android_project = create(:project, :android)
      android_key = create(:api_key, project: android_project, user: android_project.user)
      context = JSON.parse(Rails.root.join("spec/fixtures/files/android_error_payload.json").read).fetch("context").merge(
        "session_id" => "session-123",
        "installation_id_hash" => "rotating-pseudonym"
      )
      event = create(:ingest_event, project: android_project, api_key: android_key, message: "Impact event", context: context)

      group = described_class.call(event)
      occurrence = group.error_occurrences.sole

      expect(occurrence).to have_attributes(mechanism: "handled_exception", release: "1.4.0+42", telemetry_schema_version: 1)
      expect(occurrence.installation_hash).to match(/\A[0-9a-f]{64}\z/)
      expect(occurrence.session_hash).to match(/\A[0-9a-f]{64}\z/)
      expect(occurrence.dimensions).to include("device_model" => "Pixel 8", "api_level" => "35")

      described_class.call(event.reload)
      expect(group.reload.error_occurrences.count).to eq(1)
    end
  end
end
