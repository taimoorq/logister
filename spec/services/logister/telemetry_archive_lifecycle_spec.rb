# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Telemetry archive lifecycle", type: :model do
  class LifecycleArchiveStorage
    attr_reader :uploads
    attr_accessor :on_download

    def initialize
      @objects = {}
      @uploads = []
      @fail_next_upload = false
    end

    def fail_next_upload!
      @fail_next_upload = true
    end

    def upload(key, io, checksum:, content_type:)
      if @fail_next_upload
        @fail_next_upload = false
        raise "temporary object storage failure"
      end

      payload = io.read
      @objects[key] = payload
      @uploads << { key: key, payload: payload, checksum: checksum, content_type: content_type }
    end

    def download(key)
      callback = @on_download
      @on_download = nil
      callback&.call
      @objects.fetch(key)
    end

    def exist?(key) = @objects.key?(key)
    def delete(key) = @objects.delete(key)
    def corrupt!(key) = @objects[key] = "corrupt"
  end

  let(:now) { Time.zone.parse("2026-08-08 12:00:00") }
  let(:project) { create(:project) }
  let(:storage) { LifecycleArchiveStorage.new }

  it "retries a failed manifest with the same deterministic key and completes verification" do
    event = create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
    storage.fail_next_upload!

    expect {
      Logister::TelemetryArchiveExporter.new(
        record_type: "ingest_events",
        scope: "hot_events",
        project: project,
        before: now - 30.days,
        event_types: [ "log" ],
        storage_service: storage
      ).call
    }.to raise_error(Logister::TelemetryArchiveExporter::Error, /temporary object storage failure/)

    archive = project.telemetry_archives.failed.sole
    object_key = archive.object_records.sole.object_key
    expect(archive.object_records.sole.normalized_source_references).to eq([
      { "id" => event.id, "timestamp" => event.occurred_at.utc.iso8601(6) }
    ])

    result = Logister::TelemetryArchiveRetry.new(archive: archive, storage_service: storage).call

    expect(result).to include(rows: 1, verified: true)
    expect(archive.reload).to be_verified
    expect(archive.retry_count).to eq(1)
    expect(archive.object_records.sole.object_key).to eq(object_key)
    expect(storage.uploads.sole.fetch(:key)).to eq(object_key)
  end

  it "deletes only exact verified references and leaves a late old event for the next run" do
    policy = create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      archive_enabled: true,
      archive_before_delete: true
    )
    api_key = create(:api_key, project: project, user: project.user)
    original = create(:ingest_event, :log, project: project, api_key: api_key, occurred_at: now - 45.days)
    late = nil
    storage.on_download = lambda do
      late = create(:ingest_event, :log, project: project, api_key: api_key, occurred_at: now - 50.days)
    end

    result = Logister::ProjectRetentionRunner.new(
      project: project,
      policy: policy,
      storage_service: storage,
      now: now
    ).call

    expect(result.dig(:deleted, :hot_events)).to eq(1)
    expect(IngestEvent.exists?(original.id)).to be(false)
    expect(IngestEvent.exists?(late.id)).to be(true)
    archive = project.telemetry_archives.completed.find_by!(scope: "hot_events")
    expect(archive.source_deleted_rows).to eq(1)
    expect(archive.source_deleted_at).to be_present
  end

  it "protects archived error rows when their group reopens before source cleanup" do
    policy = create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      error_retention_days: 30,
      archive_enabled: true,
      archive_before_delete: true
    )
    group = create(
      :error_group,
      :resolved,
      :with_occurrence,
      project: project,
      first_seen_at: now - 60.days,
      last_seen_at: now - 45.days
    )
    archived_event_id = group.latest_event_id
    storage.on_download = -> { group.reload.reopen! }

    result = Logister::ProjectRetentionRunner.new(
      project: project,
      policy: policy,
      storage_service: storage,
      now: now
    ).call

    archive = project.telemetry_archives.completed.find_by!(scope: "error_events")
    expect(result.dig(:deleted, :error_events)).to eq(0)
    expect(group.reload).to be_unresolved
    expect(IngestEvent.exists?(archived_event_id)).to be(true)
    expect(archive.source_deleted_at).to be_nil
    expect(archive.source_deleted_rows).to eq(0)
    expect(archive.lifecycle_metadata.dig("source_cleanup", "protected_reopened_group_rows")).to eq(1)
  end

  it "defers exact event and span manifest cleanup until their deliveries complete" do
    policy = create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      archive_enabled: true,
      archive_before_delete: true
    )
    event = create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
    span = create(:trace_span, project: project, started_at: now - 45.days)
    event_delivery = create_delivery(event, status: "completed")
    span_delivery = create_delivery(span, status: "completed")
    event_archive = archive_source(scope: "hot_events", record_type: "ingest_events")
    span_archive = archive_source(scope: "trace_spans", record_type: "trace_spans")
    event_delivery.update!(status: "retrying", completed_at: nil)
    span_delivery.update!(status: "terminal_failed", completed_at: nil)

    first = Logister::ProjectRetentionRunner.new(
      project: project,
      policy: policy,
      storage_service: storage,
      now: now
    ).call

    expect(first[:recovered_deletions]).to include(hot_events: 0, trace_spans: 0)
    expect(first[:protected_by_delivery]).to include(hot_events: 1, trace_spans: 1)
    expect(IngestEvent.exists?(event.id)).to be(true)
    expect(TraceSpan.exists?(span.id)).to be(true)
    expect(event_archive.reload.source_deleted_at).to be_nil
    expect(span_archive.reload.source_deleted_at).to be_nil
    expect(event_archive.lifecycle_metadata.dig("source_cleanup", "protected_delivery_rows")).to eq(1)
    expect(span_archive.lifecycle_metadata.dig("source_cleanup", "protected_delivery_rows")).to eq(1)
    expect(project.telemetry_archives.where(scope: "hot_events").count).to eq(1)
    expect(project.telemetry_archives.where(scope: "trace_spans").count).to eq(1)

    event_delivery.update!(status: "completed", completed_at: now)
    span_delivery.update!(status: "completed", completed_at: now)
    second = Logister::ProjectRetentionRunner.new(
      project: project,
      policy: policy,
      storage_service: storage,
      now: now + 1.minute
    ).call

    expect(second[:recovered_deletions]).to include(hot_events: 1, trace_spans: 1)
    expect(IngestEvent.exists?(event.id)).to be(false)
    expect(TraceSpan.exists?(span.id)).to be(false)
    expect(event_archive.reload.source_deleted_at).to be_present
    expect(span_archive.reload.source_deleted_at).to be_present
  end

  it "reapplies a lengthened retention policy before delayed manifest cleanup" do
    policy = create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      archive_enabled: true,
      archive_before_delete: true
    )
    event = create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
    delivery = create_delivery(event, status: "completed")
    archive = archive_source(scope: "hot_events", record_type: "ingest_events")
    delivery.update!(status: "terminal_failed", completed_at: nil)

    Logister::ProjectRetentionRunner.new(
      project: project,
      policy: policy,
      storage_service: storage,
      now: now
    ).call
    policy.update!(hot_retention_days: 90)
    delivery.update!(status: "completed", completed_at: now)

    result = Logister::ProjectRetentionRunner.new(
      project: project,
      policy: policy,
      storage_service: storage,
      now: now + 1.minute
    ).call

    expect(result.dig(:recovered_deletions, :hot_events)).to eq(0)
    expect(IngestEvent.exists?(event.id)).to be(true)
    expect(archive.reload.source_deleted_at).to be_nil
  end

  it "re-verifies object bytes immediately before delayed source cleanup" do
    policy = create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      archive_enabled: true,
      archive_before_delete: true
    )
    event = create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
    delivery = create_delivery(event, status: "completed")
    archive = archive_source(scope: "hot_events", record_type: "ingest_events")
    delivery.update!(status: "retrying", completed_at: nil)

    Logister::ProjectRetentionRunner.new(
      project: project,
      policy: policy,
      storage_service: storage,
      now: now
    ).call
    storage.corrupt!(archive.object_records.sole.object_key)
    delivery.update!(status: "completed", completed_at: now)

    expect {
      Logister::ProjectRetentionRunner.new(
        project: project,
        policy: policy,
        storage_service: storage,
        now: now + 1.minute
      ).call
    }.to raise_error(Logister::TelemetryArchiveInspector::VerificationError)

    expect(IngestEvent.exists?(event.id)).to be(true)
    expect(archive.reload.source_deleted_at).to be_nil
  end

  it "restores verified rows idempotently" do
    event = create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
    archive_result = Logister::TelemetryArchiveExporter.new(
      record_type: "ingest_events",
      scope: "hot_events",
      project: project,
      before: now - 30.days,
      event_types: [ "log" ],
      storage_service: storage
    ).call
    archive = TelemetryArchive.find(archive_result.fetch(:archive_id))
    IngestEvent.for_partition_reference(id: event.id, occurred_at: event.occurred_at).delete_all

    first = Logister::TelemetryArchiveRestore.new(archive: archive, storage_service: storage).call
    second = Logister::TelemetryArchiveRestore.new(archive: archive.reload, storage_service: storage).call

    expect(first).to include(restored: 1, skipped: 0)
    expect(second).to include(restored: 0, skipped: 1)
    expect(IngestEvent.for_partition_reference(id: event.id, occurred_at: event.occurred_at)).to exist
    expect(archive.reload.status).to eq("restored")
  end

  it "restores versioned mobile derived evidence with its source event" do
    mobile_project = create(:project, :ios)
    event = create(:ingest_event, project: mobile_project, occurred_at: now - 45.days)
    enrichment = create(
      :mobile_event_enrichment,
      :apple_symbolication,
      project: mobile_project,
      event_uuid: event.uuid,
      event_occurred_at: event.occurred_at,
      artifact_checksum_sha256: Digest::SHA256.hexdigest("artifact"),
      data: {
        "schema_version" => 1,
        "frames" => [ { "address" => "0x100001234", "qualified_method" => "CheckoutStore.commit()" } ]
      }
    )
    archive_result = Logister::TelemetryArchiveExporter.new(
      record_type: "ingest_events",
      scope: "hot_events",
      project: mobile_project,
      before: now - 30.days,
      storage_service: storage
    ).call
    archive = TelemetryArchive.find(archive_result.fetch(:archive_id))
    MobileEventEnrichment.where(id: enrichment.id).delete_all
    IngestEvent.for_partition_reference(id: event.id, occurred_at: event.occurred_at).delete_all

    result = Logister::TelemetryArchiveRestore.new(archive:, storage_service: storage).call

    restored = mobile_project.mobile_event_enrichments.apple_symbolication.find_by!(event_uuid: event.uuid)
    expect(result).to include(restored: 1, restored_derived: 1)
    expect(restored).to have_attributes(
      uuid: enrichment.uuid,
      artifact_checksum_sha256: Digest::SHA256.hexdigest("artifact"),
      tool_name: "apple_atos",
      tool_version: "adapter-1; Xcode test"
    )
    expect(restored.data.dig("frames", 0)).to include(
      "address" => "0x100001234",
      "qualified_method" => "CheckoutStore.commit()"
    )
  end

  it "does not restore source rows after project purge is tombstoned" do
    event = create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
    archive_result = Logister::TelemetryArchiveExporter.new(
      record_type: "ingest_events",
      scope: "hot_events",
      project: project,
      before: now - 30.days,
      event_types: [ "log" ],
      storage_service: storage
    ).call
    archive = TelemetryArchive.find(archive_result.fetch(:archive_id))
    IngestEvent.for_partition_reference(id: event.id, occurred_at: event.occurred_at).delete_all
    project.update!(purge_requested_at: now)

    expect {
      Logister::TelemetryArchiveRestore.new(archive: archive, storage_service: storage).call
    }.to raise_error(Logister::TelemetryArchiveRestore::RestoreError, /purge is pending/)

    expect(IngestEvent.for_partition_reference(id: event.id, occurred_at: event.occurred_at)).not_to exist
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

  def archive_source(scope:, record_type:)
    result = Logister::TelemetryArchiveExporter.new(
      record_type: record_type,
      scope: scope,
      project: project,
      before: now - 30.days,
      storage_service: storage
    ).call
    TelemetryArchive.find(result.fetch(:archive_id))
  end
end
