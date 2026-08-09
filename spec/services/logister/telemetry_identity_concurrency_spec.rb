# frozen_string_literal: true

require "rails_helper"
require "timeout"

RSpec.describe "Telemetry source identity concurrency", type: :model do
  self.use_transactional_tests = false

  TEST_UUIDS = %w[
    aaaaaaaa-1111-4111-8111-111111111111
    bbbbbbbb-2222-4222-8222-222222222222
    cccccccc-3333-4333-8333-333333333333
    dddddddd-4444-4444-8444-444444444444
    eeeeeeee-5555-4555-8555-555555555555
  ].freeze
  RECORDED_AT = "2026-08-08T12:00:00Z"

  around do |example|
    config = Rails.configuration.x.logister
    previous_mode = config.clickhouse_mode
    previous_enabled = config.clickhouse_enabled
    config.clickhouse_mode = "disabled"
    config.clickhouse_enabled = false
    example.run
  ensure
    config.clickhouse_mode = previous_mode
    config.clickhouse_enabled = previous_enabled
  end

  after do
    project_ids = [ projects(:one).id, projects(:two).id ]
    TelemetryIdempotencyKey.where(project_id: project_ids, client_identifier: TEST_UUIDS).delete_all
    TelemetryProjectionWatermark.where(
      project_id: project_ids,
      signal: "log",
      destination: "clickhouse_event",
      bucket_start_at: Time.zone.parse(RECORDED_AT).beginning_of_hour
    ).delete_all
    IngestEvent.where(project_id: project_ids, uuid: TEST_UUIDS).delete_all
    TraceSpan.where(project_id: project_ids, uuid: TEST_UUIDS).delete_all
  end

  it "accepts one event source when the same project identity arrives concurrently" do
    project_id = projects(:one).id
    api_key_id = api_keys(:one).id
    uuid = TEST_UUIDS.fetch(0)

    results = concurrently(2) do
      persist_event(project_id: project_id, api_key_id: api_key_id, uuid: uuid)
    end

    expect(results.map(&:duplicate?)).to contain_exactly(false, true)
    expect(IngestEvent.where(project_id: project_id, uuid: uuid).count).to eq(1)
    expect(TelemetryIdempotencyKey.where(project_id: project_id, client_identifier: uuid).count).to eq(1)
  end

  it "accepts one span source when the same project identity arrives concurrently" do
    project_id = projects(:one).id
    api_key_id = api_keys(:one).id
    uuid = TEST_UUIDS.fetch(1)

    results = concurrently(2) do
      persist_span(project_id: project_id, api_key_id: api_key_id, uuid: uuid)
    end

    expect(results.map(&:duplicate?)).to contain_exactly(false, true)
    expect(TraceSpan.where(project_id: project_id, uuid: uuid).count).to eq(1)
    expect(TelemetryIdempotencyKey.where(project_id: project_id, client_identifier: uuid).count).to eq(1)
  end

  it "allows the same event and span UUIDs in different projects" do
    project_ids = [ projects(:one).id, projects(:two).id ]
    api_key_ids = [ api_keys(:one).id, api_keys(:two).id ]

    event_results = concurrently(2) do |index|
      persist_event(
        project_id: project_ids.fetch(index),
        api_key_id: api_key_ids.fetch(index),
        uuid: TEST_UUIDS.fetch(2)
      )
    end
    span_results = concurrently(2) do |index|
      persist_span(
        project_id: project_ids.fetch(index),
        api_key_id: api_key_ids.fetch(index),
        uuid: TEST_UUIDS.fetch(3)
      )
    end

    expect(event_results.map(&:duplicate?)).to eq([ false, false ])
    expect(span_results.map(&:duplicate?)).to eq([ false, false ])
    expect(IngestEvent.where(uuid: TEST_UUIDS.fetch(2)).pluck(:project_id)).to contain_exactly(*project_ids)
    expect(TraceSpan.where(uuid: TEST_UUIDS.fetch(3)).pluck(:project_id)).to contain_exactly(*project_ids)
  end

  it "never creates a source-dependent intent after concurrent source retirement" do
    project = projects(:one)
    api_key = api_keys(:one)
    uuid = TEST_UUIDS.fetch(4)
    first = persist_event(project_id: project.id, api_key_id: api_key.id, uuid: uuid)
    runner = Logister::ProjectRetentionRunner.new(project: project, policy: Object.new, batch_size: 1)

    concurrently(2) do |index|
      if index.zero?
        persist_event(
          project_id: project.id,
          api_key_id: api_key.id,
          uuid: uuid,
          clickhouse_writable: true
        )
      else
        runner.__send__(
          :delete_events_by_references,
          [ [ first.event.id, first.event.occurred_at ] ]
        )
      end
    end

    key = TelemetryIdempotencyKey.find_by!(project_id: project.id, client_identifier: uuid)
    deliveries = key.telemetry_outbox_event.telemetry_deliveries.reload
    if key.source_retired?
      expect(IngestEvent.for_partition_reference(id: first.event.id, occurred_at: first.event.occurred_at)).to be_empty
      expect(deliveries).to be_empty
    else
      expect(IngestEvent.for_partition_reference(id: first.event.id, occurred_at: first.event.occurred_at)).to exist
      expect(deliveries).to contain_exactly(have_attributes(destination: "clickhouse_event", status: "pending"))
    end
  end

  private

  def concurrently(count, &work)
    ready = Queue.new
    release = Queue.new
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          release.pop
          work.call(index)
        end
      end
    end
    count.times { ready.pop }
    count.times { release << true }
    Timeout.timeout(10) { threads.map(&:value) }
  ensure
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end
  end

  def persist_event(project_id:, api_key_id:, uuid:, clickhouse_writable: nil)
    project = Project.find(project_id)
    IngestEventPersistence.new(
      project: project,
      api_key: ApiKey.find(api_key_id),
      attributes: {
        uuid: uuid,
        event_type: "log",
        message: "concurrent event",
        occurred_at: Time.zone.parse(RECORDED_AT),
        context: { "environment" => "test" }
      },
      clickhouse_writable: clickhouse_writable
    ).call
  end

  def persist_span(project_id:, api_key_id:, uuid:)
    project = Project.find(project_id)
    TraceSpanPersistence.new(
      project: project,
      api_key: ApiKey.find(api_key_id),
      attributes: {
        uuid: uuid,
        trace_id: "concurrent-trace",
        span_id: "concurrent-span",
        name: "concurrent span",
        kind: "internal",
        duration_ms: 1.0,
        started_at: Time.zone.parse(RECORDED_AT),
        context: { "environment" => "test" }
      }
    ).call
  end
end
