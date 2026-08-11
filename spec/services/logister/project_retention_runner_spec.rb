# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ProjectRetentionRunner, type: :model do
  include ActiveJob::TestHelper

  class FakeRetentionArchiveStorage
    attr_reader :uploads

    def initialize
      @uploads = []
      @objects = {}
    end

    def upload(key, io, checksum:, content_type:)
      payload = io.read
      @objects[key] = payload
      @uploads << {
        key: key,
        payload: payload,
        checksum: checksum,
        content_type: content_type
      }
    end

    def download(key) = @objects.fetch(key)
    def exist?(key) = @objects.key?(key)
    def delete(key) = @objects.delete(key)
  end

  class FailingRetentionArchiveStorage
    def upload(*)
      raise RuntimeError, "storage unavailable"
    end
  end

  let(:now) { Time.zone.parse("2026-05-22 12:00:00") }
  let(:project) { create(:project) }
  let(:policy) do
    create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      error_retention_days: 30
    )
  end

  before { clear_enqueued_jobs }

  it "reports candidates without deleting data during a dry run" do
    old_log = create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
    recent_log = create(:ingest_event, :log, project: project, occurred_at: now - 5.days)
    old_error = create(:ingest_event, project: project, occurred_at: now - 45.days)
    old_span = create(:trace_span, project: project, started_at: now - 45.days)

    result = described_class.new(project: project, policy: policy, dry_run: true, now: now).call

    expect(result[:candidates]).to include(hot_events: 1, trace_spans: 1, closed_error_groups: 0)
    expect(result[:deleted]).to include(hot_events: 0, trace_spans: 0, closed_error_groups: 0)
    expect(IngestEvent.where(id: [ old_log.id, recent_log.id, old_error.id ]).count).to eq(3)
    expect(TraceSpan.exists?(old_span.id)).to be true
    expect(policy.reload.last_retention_run_at).to be_nil
  end

  it "deletes old hot telemetry for one project and clears event references" do
    other_project = create(:project)
    old_check_in = create(:ingest_event, :check_in, project: project, occurred_at: now - 45.days)
    old_other_event = create(:ingest_event, :log, project: other_project, occurred_at: now - 45.days)
    recent_event = create(:ingest_event, :transaction, project: project, occurred_at: now - 5.days)
    old_error = create(:ingest_event, project: project, occurred_at: now - 45.days)
    old_span = create(:trace_span, project: project, started_at: now - 45.days)
    monitor = create(:check_in_monitor, project: project, last_event: old_check_in)

    result = described_class.new(project: project, policy: policy, now: now).call

    expect(result[:deleted]).to include(hot_events: 1, trace_spans: 1, closed_error_groups: 0)
    expect(IngestEvent.exists?(old_check_in.id)).to be false
    expect(IngestEvent.exists?(old_other_event.id)).to be true
    expect(IngestEvent.exists?(recent_event.id)).to be true
    expect(IngestEvent.exists?(old_error.id)).to be true
    expect(TraceSpan.exists?(old_span.id)).to be false
    expect(monitor.reload.last_event).to be_nil
    expect(monitor.last_event_occurred_at).to be_nil
    expect(policy.reload.last_retention_run_at.to_i).to eq(now.to_i)
  end

  it "retains event and span sources for every unfinished delivery state and retries after completion" do
    statuses = %w[pending processing retrying terminal_failed]
    protected_records = statuses.each_with_index.map do |status, index|
      record = if index.even?
        create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
      else
        create(:trace_span, project: project, started_at: now - 45.days)
      end
      [ record, create_delivery(record, status: status) ]
    end
    completed_event = create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
    completed_span = create(:trace_span, project: project, started_at: now - 45.days)
    create_delivery(completed_event, status: "completed")
    create_delivery(completed_span, status: "completed")

    first = described_class.new(project: project, policy: policy, now: now).call

    expect(first[:protected_by_delivery]).to include(hot_events: 2, trace_spans: 2)
    expect(first[:deleted]).to include(hot_events: 1, trace_spans: 1)
    expect(IngestEvent.exists?(completed_event.id)).to be(false)
    expect(TraceSpan.exists?(completed_span.id)).to be(false)
    expect(idempotency_key_for(completed_event).reload).to be_source_retired
    expect(idempotency_key_for(completed_span).reload).to be_source_retired
    protected_records.each { |record, _delivery| expect(record.class.exists?(record.id)).to be(true) }
    protected_records.each { |record, _delivery| expect(idempotency_key_for(record).reload).not_to be_source_retired }

    protected_records.each do |_record, delivery|
      delivery.update!(status: "completed", completed_at: now)
    end
    second = described_class.new(project: project, policy: policy, now: now + 1.minute).call

    expect(second[:protected_by_delivery]).to include(hot_events: 0, trace_spans: 0)
    expect(second[:deleted]).to include(hot_events: 2, trace_spans: 2)
    protected_records.each { |record, _delivery| expect(record.class.exists?(record.id)).to be(false) }
    protected_records.each { |record, _delivery| expect(idempotency_key_for(record).reload).to be_source_retired }
  end

  it "keeps a closed error group and its event until the event delivery completes" do
    group = create(
      :error_group,
      :resolved,
      :with_occurrence,
      project: project,
      first_seen_at: now - 60.days,
      last_seen_at: now - 45.days
    )
    event = group.latest_event_record
    delivery = create_delivery(event, status: "terminal_failed")

    first = described_class.new(project: project, policy: policy, now: now).call

    expect(first.dig(:protected_by_delivery, :error_events)).to eq(1)
    expect(first.dig(:deleted, :closed_error_groups)).to eq(0)
    expect(ErrorGroup.exists?(group.id)).to be(true)
    expect(IngestEvent.exists?(event.id)).to be(true)
    expect(ErrorOccurrence.where(error_group_id: group.id, ingest_event_id: event.id)).to exist

    delivery.update!(status: "completed", completed_at: now)
    second = described_class.new(project: project, policy: policy, now: now + 1.minute).call

    expect(second.dig(:deleted, :closed_error_groups)).to eq(1)
    expect(ErrorGroup.exists?(group.id)).to be(false)
    expect(IngestEvent.exists?(event.id)).to be(false)
  end

  it "deletes an archive-sized reference batch without recursive Arel conditions" do
    old_events = create_list(:ingest_event, 1_000, :log, project: project, occurred_at: now - 45.days)

    result = described_class.new(project: project, policy: policy, batch_size: 1_000, now: now).call

    expect(result[:deleted][:hot_events]).to eq(1_000)
    expect(IngestEvent.where(id: old_events.map(&:id)).count).to eq(0)
  end

  it "prunes closed error groups only after their retention window" do
    closed_group = create(
      :error_group,
      :resolved,
      :with_occurrence,
      project: project,
      first_seen_at: now - 60.days,
      last_seen_at: now - 45.days
    )
    closed_event_id = closed_group.latest_event_id
    open_group = create(
      :error_group,
      :with_occurrence,
      project: project,
      first_seen_at: now - 60.days,
      last_seen_at: now - 45.days
    )

    result = described_class.new(project: project, policy: policy, now: now).call

    expect(result[:deleted][:closed_error_groups]).to eq(1)
    expect(ErrorGroup.exists?(closed_group.id)).to be false
    expect(IngestEvent.exists?(closed_event_id)).to be false
    expect(ErrorGroup.exists?(open_group.id)).to be true
    expect(IngestEvent.exists?(open_group.latest_event_id)).to be true
  end

  it "archives project-scoped telemetry before deleting when configured" do
    storage = FakeRetentionArchiveStorage.new
    policy.update!(archive_enabled: true, archive_before_delete: true)
    create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
    create(
      :error_group,
      :resolved,
      :with_occurrence,
      project: project,
      first_seen_at: now - 60.days,
      last_seen_at: now - 45.days
    )
    create(:trace_span, project: project, started_at: now - 45.days)
    create(:ingest_event, :log, occurred_at: now - 45.days)

    result = described_class.new(project: project, policy: policy, storage_service: storage, now: now).call

    expect(result[:archives].map { |archive| archive.fetch(:scope) }).to include(:hot_events, :trace_spans, :error_events)
    expect(project.telemetry_archives.completed.pluck(:scope)).to include("hot_events", "trace_spans", "error_events")
    expect(project.telemetry_archives.completed).to all(be_verified)
    expect(project.telemetry_archives.completed).to all(have_attributes(source_deleted_at: be_present))
    expect(storage.uploads.map { |upload| upload.fetch(:key) }).to all(include("project=#{project.uuid}"))
    expect(policy.reload.last_archive_run_at.to_i).to eq(now.to_i)
  end

  it "records and notifies retention archive failures" do
    policy.update!(archive_enabled: true, archive_before_delete: true)
    create(:ingest_event, :log, project: project, occurred_at: now - 45.days)

    expect {
      described_class.new(project: project, policy: policy, storage_service: FailingRetentionArchiveStorage.new, now: now).call
    }.to raise_error(Logister::TelemetryArchiveExporter::Error, /storage unavailable/)

    archive = project.telemetry_archives.failed.sole
    expect(archive.scope).to eq("hot_events")
    expect(archive.error_message).to include("storage unavailable")
    expect(ProjectRetentionNotificationJob).to have_been_enqueued.with(
      project.id,
      hash_including("scope" => "hot_events", "error_message" => include("storage unavailable"))
    )
  end

  def create_delivery(record, status:)
    recorded_at = TelemetryIdempotencyKey.recorded_at_for(record)
    record_type = record.class.base_class.name
    key = TelemetryIdempotencyKey.create!(
      project: record.project,
      client_identifier: record.uuid,
      signal: record.is_a?(TraceSpan) ? "span" : record.event_type,
      record_type: record_type,
      record_id: record.id,
      recorded_at: recorded_at,
      expires_at: now + TelemetryIdempotencyKey::RETENTION
    )
    outbox = TelemetryOutboxEvent.create!(
      project: record.project,
      telemetry_idempotency_key: key,
      client_identifier: record.uuid,
      signal: key.signal,
      record_type: record_type,
      record_id: record.id,
      recorded_at: recorded_at,
      accepted_at: now
    )
    TelemetryDelivery.create!(
      project: record.project,
      telemetry_outbox_event: outbox,
      destination: record.is_a?(TraceSpan) ? "clickhouse_span" : "clickhouse_event",
      status: status,
      available_at: now,
      completed_at: (now if status == "completed")
    )
  end

  def idempotency_key_for(record)
    TelemetryIdempotencyKey.find_by!(project_id: record.project_id, client_identifier: record.uuid)
  end
end
