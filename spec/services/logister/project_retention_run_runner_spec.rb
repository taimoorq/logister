# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ProjectRetentionRunRunner, type: :model do
  class DurableRetentionArchiveStorage
    attr_reader :uploads

    def initialize
      @objects = {}
      @uploads = []
    end

    def upload(key, io, checksum:, content_type:)
      payload = io.read
      @objects[key] = payload
      @uploads << { key: key, payload: payload, checksum: checksum, content_type: content_type }
    end

    def download(key) = @objects.fetch(key)
    def exist?(key) = @objects.key?(key)
    def delete(key) = @objects.delete(key)
  end

  let(:now) { Time.zone.parse("2026-08-11 12:00:00") }
  let(:run) { create(:project_retention_run, scheduled_for: now) }

  it "commits authoritative completion and clears attempt ownership" do
    result = {
      candidates: { hot_events: 2, trace_spans: 0, closed_error_groups: 0 },
      deleted: { hot_events: 2 },
      continuation_required: false
    }
    runner = instance_double(Logister::ProjectRetentionRunner, call: result)
    allow(Logister::ProjectRetentionRunner).to receive(:new).and_return(runner)

    outcome = described_class.new(run: run, now: now).call

    expect(outcome).to include(action: :complete, status: "completed", result: result)
    expect(run.reload).to have_attributes(
      status: "completed",
      phase: "finalizing",
      attempt_token: nil,
      completed_at: now,
      rows_total: 2,
      rows_completed: 2
    )
  end

  it "records terminal and checkpoint timestamps when the attempt actually finishes" do
    finished_at = now + 20.seconds
    clock_time = now
    result = {
      candidates: { hot_events: 2, trace_spans: 0, closed_error_groups: 0 },
      deleted: { hot_events: 2 },
      continuation_required: false
    }
    runner = instance_double(Logister::ProjectRetentionRunner)
    allow(runner).to receive(:call) do
      clock_time = finished_at
      result
    end
    allow(Logister::ProjectRetentionRunner).to receive(:new).and_return(runner)

    described_class.new(run: run, now: now, clock: -> { clock_time }).call

    expect(run.reload).to have_attributes(
      started_at: now,
      heartbeat_at: finished_at,
      last_checkpoint_at: finished_at,
      completed_at: finished_at
    )
  end

  it "checkpoints a bounded continuation without marking completion" do
    result = { archives: [], deleted: {}, continuation_required: true }
    allow(Logister::ProjectRetentionRunner).to receive(:new).and_return(
      instance_double(Logister::ProjectRetentionRunner, call: result)
    )

    outcome = described_class.new(run: run, now: now).call

    expect(outcome).to include(action: :continue, status: "queued")
    expect(run.reload).to have_attributes(
      status: "queued",
      attempt_token: nil,
      completed_at: nil,
      last_checkpoint_at: now
    )
  end

  it "schedules a continuation from the actual checkpoint time" do
    checkpointed_at = now + 20.seconds
    clock_time = now
    result = { archives: [], deleted: {}, continuation_required: true }
    runner = instance_double(Logister::ProjectRetentionRunner)
    allow(runner).to receive(:call) do
      clock_time = checkpointed_at
      result
    end
    allow(Logister::ProjectRetentionRunner).to receive(:new).and_return(runner)

    described_class.new(run: run, now: now, clock: -> { clock_time }).call

    expect(run.reload).to have_attributes(
      status: "queued",
      heartbeat_at: checkpointed_at,
      last_checkpoint_at: checkpointed_at,
      available_at: checkpointed_at + described_class::CONTINUATION_DELAY
    )
  end

  it "does not let a stale attempt overwrite a successor fence" do
    allow(Logister::ProjectRetentionRunner).to receive(:new) do |**arguments|
      ProjectRetentionRun.where(id: run.id).update_all(
        status: "retrying",
        fence_version: run.reload.fence_version + 1,
        attempt_token: nil
      )
      arguments.fetch(:write_fence).call
    end

    outcome = described_class.new(run: run, now: now).call

    expect(outcome).to include(action: :fenced, status: "retrying")
    expect(run.reload.status).to eq("retrying")
  end

  it "records an integrity failure as terminal" do
    error = Logister::TelemetryArchiveInspector::VerificationError.new("checksum mismatch")
    allow(Logister::ProjectRetentionRunner).to receive(:new).and_return(
      instance_double(Logister::ProjectRetentionRunner, call: nil).tap do |runner|
        allow(runner).to receive(:call).and_raise(error)
      end
    )

    outcome = described_class.new(run: run, now: now).call

    expect(outcome).to include(action: :failed, status: "failed", error: error)
    expect(run.reload).to have_attributes(
      status: "failed",
      attempt_token: nil,
      failed_at: now,
      last_error_class: "Logister::TelemetryArchiveInspector::VerificationError"
    )
  end

  it "records a transient dependency failure for bounded retry" do
    error = RuntimeError.new("object storage unavailable")
    allow(Logister::ProjectRetentionRunner).to receive(:new).and_return(
      instance_double(Logister::ProjectRetentionRunner, call: nil).tap do |runner|
        allow(runner).to receive(:call).and_raise(error)
      end
    )

    outcome = described_class.new(run: run, now: now).call

    expect(outcome).to include(action: :retry, status: "retrying", error: error)
    expect(outcome.fetch(:wait)).to be_between(2.seconds, 6.seconds)
    expect(run.reload).to have_attributes(
      status: "retrying",
      attempt_token: nil,
      failed_at: nil,
      last_error_class: "RuntimeError"
    )
    expect(run.available_at).to be > now
  end

  it "ignores a duplicate delivery while a fresh attempt owns the run" do
    run.update!(
      status: "running",
      attempt_token: SecureRandom.uuid,
      fence_version: 2,
      heartbeat_at: now,
      available_at: nil
    )
    allow(Logister::ProjectRetentionRunner).to receive(:new)

    outcome = described_class.new(run: run, now: now).call

    expect(outcome).to include(action: :noop, status: "running")
    expect(Logister::ProjectRetentionRunner).not_to have_received(:new)
  end

  it "advances a real archive through bounded upload, verification, and cleanup attempts" do
    stub_const("Logister::ProjectRetentionRunRunner::DEFAULT_OBJECTS_PER_ATTEMPT", 1)
    project = create(:project)
    create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      archive_enabled: true,
      archive_before_delete: true
    )
    events = create_list(:ingest_event, 2, :log, project: project, occurred_at: now - 45.days)
    durable_run = Logister::ProjectRetentionRunCoordinator.create_or_find!(
      project: project,
      scheduled_for: now,
      dry_run: false,
      trigger_kind: "scheduled"
    ).run
    durable_run.update!(available_at: now)
    storage = DurableRetentionArchiveStorage.new
    actions = []

    15.times do |index|
      outcome = described_class.new(run: durable_run.reload, storage_service: storage, now: now + index * 2.seconds).call
      actions << outcome.fetch(:action)
      break if outcome.fetch(:action) == :complete
    end

    archive = durable_run.telemetry_archives.find_by!(scope: "hot_events")
    expect(actions).to include(:continue)
    expect(actions.last).to eq(:complete)
    expect(durable_run.reload.status).to eq("completed")
    expect(archive).to be_verified
    expect(archive.source_deleted_at).to be_present
    expect(archive.object_record_scope.pluck(:source_cleanup_status)).to all(eq("completed"))
    expect(IngestEvent.where(id: events.map(&:id))).to be_empty
    expect(storage.uploads.pluck(:key).uniq.size).to eq(1)
    expect(storage.uploads.size).to eq(1)
  end

  it "keeps a run open until a manifest larger than one attempt is verified and its sources deleted" do
    stub_const("Logister::ProjectRetentionRunRunner::DEFAULT_OBJECTS_PER_ATTEMPT", 1)
    stub_const("Logister::ProjectRetentionRunner::DEFAULT_BATCH_SIZE", 1)
    project = create(:project)
    policy = create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      archive_enabled: true,
      archive_before_delete: true
    )
    events = create_list(:ingest_event, 3, :metric, project: project, occurred_at: now - 45.days)
    durable_run = Logister::ProjectRetentionRunCoordinator.create_or_find!(
      project: project,
      scheduled_for: now,
      dry_run: false,
      trigger_kind: "scheduled"
    ).run
    durable_run.update!(available_at: now)
    storage = DurableRetentionArchiveStorage.new

    actions = run_until_complete(durable_run, storage)

    archive = durable_run.telemetry_archives.find_by!(scope: "hot_events")
    expect(actions.first).to eq(:continue)
    expect(actions.last).to eq(:complete)
    expect(archive).to be_verified
    expect(archive.object_record_scope.count).to eq(3)
    expect(archive.source_deleted_at).to be_present
    expect(IngestEvent.where(id: events.map(&:id))).to be_empty
    expect(storage.uploads.size).to eq(3)
    final = durable_run.reload.result
    expect(final.fetch("deleted").fetch("hot_events", 0) + final.fetch("recovered_deletions").fetch("hot_events", 0)).to eq(3)
    expect(policy.reload.last_archive_run_at).to be_present
  end

  { "one object per attempt" => 1, "a whole manifest per attempt" => 25 }.each do |budget_label, objects_per_attempt|
    it "archives a backlog as capped manifests and deletes each chunk first with #{budget_label}" do
      stub_const("Logister::ProjectRetentionRunRunner::DEFAULT_OBJECTS_PER_ATTEMPT", objects_per_attempt)
      stub_const("Logister::ProjectRetentionRunRunner::DEFAULT_OBJECTS_PER_MANIFEST", 2)
      stub_const("Logister::ProjectRetentionRunner::DEFAULT_BATCH_SIZE", 1)
      project = create(:project)
      create(
        :project_retention_policy,
        project: project,
        hot_retention_days: 30,
        trace_retention_days: 30,
        archive_enabled: true,
        archive_before_delete: true
      )
      events = create_list(:ingest_event, 5, :metric, project: project, occurred_at: now - 45.days).sort_by(&:id)
      durable_run = Logister::ProjectRetentionRunCoordinator.create_or_find!(
        project: project,
        scheduled_for: now,
        dry_run: false,
        trigger_kind: "scheduled"
      ).run
      durable_run.update!(available_at: now)
      storage = DurableRetentionArchiveStorage.new
      remaining_when_second_manifest_started = nil
      allow(Logister::TelemetryArchiveExporter).to receive(:new).and_wrap_original do |original, **arguments|
        if arguments[:after_source_id] && remaining_when_second_manifest_started.nil?
          remaining_when_second_manifest_started = IngestEvent.where(id: events.map(&:id)).count
        end
        original.call(**arguments)
      end

      actions = run_until_complete(durable_run, storage)

      manifests = durable_run.telemetry_archives.where(scope: "hot_events").order(:id).to_a
      expect(actions.last).to eq(:complete)
      expect(manifests.map { |archive| archive.object_record_scope.count }).to eq([ 2, 2, 1 ])
      expect(manifests).to all(be_verified)
      expect(manifests).to all(have_attributes(source_deleted_at: be_present))
      expect(manifests.map { |archive| archive.lifecycle_metadata["after_source_id"] }).to eq(
        [ nil, manifests[0].source_max_id, manifests[1].source_max_id ]
      )
      expect(manifests.map { |archive| archive.lifecycle_metadata["enumeration_truncated"] == true }).to eq([ true, true, false ])
      expect(remaining_when_second_manifest_started).to eq(3)
      expect(IngestEvent.where(id: events.map(&:id))).to be_empty
      expect(storage.uploads.size).to eq(5)
    end
  end

  it "resumes a manifest stranded by an earlier completed run instead of uploading a duplicate" do
    stub_const("Logister::ProjectRetentionRunRunner::DEFAULT_OBJECTS_PER_ATTEMPT", 1)
    stub_const("Logister::ProjectRetentionRunner::DEFAULT_BATCH_SIZE", 1)
    project = create(:project)
    create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      archive_enabled: true,
      archive_before_delete: true
    )
    events = create_list(:ingest_event, 3, :metric, project: project, occurred_at: now - 45.days)
    storage = DurableRetentionArchiveStorage.new
    earlier_run = create(
      :project_retention_run,
      project: project,
      scheduled_for: now - 1.day,
      status: "completed",
      completed_at: now - 1.day
    )
    stranded = Logister::TelemetryArchiveExporter.new(
      record_type: "ingest_events",
      scope: "hot_events",
      project: project,
      before: now - 31.days,
      event_types: Logister::ProjectRetentionRunner::HOT_EVENT_TYPES,
      batch_size: 1,
      storage_service: storage,
      object_limit: 1,
      project_retention_run: earlier_run
    ).call
    stranded_archive = TelemetryArchive.find(stranded.fetch(:archive_id))
    expect(stranded_archive).not_to be_verified

    durable_run = Logister::ProjectRetentionRunCoordinator.create_or_find!(
      project: project,
      scheduled_for: now,
      dry_run: false,
      trigger_kind: "scheduled"
    ).run
    durable_run.update!(available_at: now)

    actions = run_until_complete(durable_run, storage)

    expect(actions.last).to eq(:complete)
    expect(project.telemetry_archives.where(scope: "hot_events").pluck(:id)).to eq([ stranded_archive.id ])
    expect(stranded_archive.reload).to be_verified
    expect(stranded_archive.project_retention_run_id).to eq(durable_run.id)
    expect(stranded_archive.lifecycle_metadata).to include("adopted_from_retention_run_id" => earlier_run.id)
    expect(stranded_archive.source_deleted_at).to be_present
    expect(IngestEvent.where(id: events.map(&:id))).to be_empty
    expect(storage.uploads.size).to eq(3)
  end

  it "leaves a manifest owned by a failed run for investigation" do
    project = create(:project)
    create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      archive_enabled: true,
      archive_before_delete: true
    )
    create(:ingest_event, :metric, project: project, occurred_at: now - 45.days)
    storage = DurableRetentionArchiveStorage.new
    failed_run = create(:project_retention_run, project: project, scheduled_for: now - 1.day, status: "failed")
    preserved = Logister::TelemetryArchiveExporter.new(
      record_type: "ingest_events",
      scope: "hot_events",
      project: project,
      before: now - 31.days,
      event_types: Logister::ProjectRetentionRunner::HOT_EVENT_TYPES,
      storage_service: storage,
      object_limit: 1,
      project_retention_run: failed_run
    ).call
    preserved_archive = TelemetryArchive.find(preserved.fetch(:archive_id))
    preserved_archive.update_columns(status: "failed", error_message: "checksum mismatch")

    durable_run = Logister::ProjectRetentionRunCoordinator.create_or_find!(
      project: project,
      scheduled_for: now,
      dry_run: false,
      trigger_kind: "scheduled"
    ).run
    durable_run.update!(available_at: now)
    run_until_complete(durable_run, storage)

    expect(preserved_archive.reload).to have_attributes(status: "failed", project_retention_run_id: failed_run.id)
    expect(durable_run.telemetry_archives.where(scope: "hot_events").sole).to be_verified
  end

  it "adopts an unlinked resumable v2 manifest instead of restarting it" do
    stub_const("Logister::ProjectRetentionRunRunner::DEFAULT_OBJECTS_PER_ATTEMPT", 1)
    project = create(:project)
    create(
      :project_retention_policy,
      project: project,
      hot_retention_days: 30,
      trace_retention_days: 30,
      archive_enabled: true,
      archive_before_delete: true
    )
    event = create(:ingest_event, :log, project: project, occurred_at: now - 45.days)
    storage = DurableRetentionArchiveStorage.new
    partial = Logister::TelemetryArchiveExporter.new(
      record_type: "ingest_events",
      scope: "hot_events",
      project: project,
      before: now - 30.days,
      event_types: [ "log" ],
      storage_service: storage,
      object_limit: 1
    ).call
    archive = TelemetryArchive.find(partial.fetch(:archive_id))
    expect(archive.project_retention_run_id).to be_nil
    expect(partial.fetch(:continuation_required)).to be(true)

    durable_run = Logister::ProjectRetentionRunCoordinator.create_or_find!(
      project: project,
      scheduled_for: now,
      dry_run: false,
      trigger_kind: "recovery"
    ).run
    durable_run.update!(available_at: now)
    outcome = described_class.new(run: durable_run, storage_service: storage, now: now).call

    expect(outcome.fetch(:action)).to eq(:complete)
    expect(archive.reload.project_retention_run_id).to eq(durable_run.id)
    expect(archive).to be_verified
    expect(archive.source_deleted_at).to be_present
    expect(IngestEvent.exists?(event.id)).to be(false)
    expect(storage.uploads.size).to eq(1)
  end

  def run_until_complete(durable_run, storage, max_attempts: 40)
    actions = []
    max_attempts.times do |index|
      outcome = described_class.new(
        run: durable_run.reload,
        storage_service: storage,
        now: now + index * 2.seconds
      ).call
      actions << outcome.fetch(:action)
      break if outcome.fetch(:action).in?(%i[complete failed])
    end
    actions
  end
end
