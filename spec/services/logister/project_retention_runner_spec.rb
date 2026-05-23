# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ProjectRetentionRunner, type: :model do
  class FakeRetentionArchiveStorage
    attr_reader :uploads

    def initialize
      @uploads = []
    end

    def upload(key, io, checksum:, content_type:)
      @uploads << {
        key: key,
        payload: io.read,
        checksum: checksum,
        content_type: content_type
      }
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
    expect(policy.reload.last_retention_run_at.to_i).to eq(now.to_i)
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
    create(:ingest_event, project: project, occurred_at: now - 45.days)
    create(:trace_span, project: project, started_at: now - 45.days)
    create(:ingest_event, :log, occurred_at: now - 45.days)

    result = described_class.new(project: project, policy: policy, storage_service: storage, now: now).call

    expect(result[:archives].map { |archive| archive.fetch(:scope) }).to include(:hot_events, :trace_spans, :error_events)
    expect(project.telemetry_archives.completed.pluck(:scope)).to include("hot_events", "trace_spans", "error_events")
    expect(storage.uploads.map { |upload| upload.fetch(:key) }).to all(include("project=#{project.uuid}"))
    expect(policy.reload.last_archive_run_at.to_i).to eq(now.to_i)
  end
end
