# frozen_string_literal: true

require "rails_helper"
require "timeout"

RSpec.describe "Telemetry database contention", type: :model do
  self.use_transactional_tests = false

  let!(:project) { create(:project, user: users(:one)) }
  let!(:api_key) { create(:api_key, project: project, user: project.user) }
  let(:recorded_at) { Time.current.utc.beginning_of_hour }

  after do
    # These examples commit across connections; delete only their private project.
    ProjectPurge.where(source_project_id: project.id).destroy_all
    IngestEvent.where(project_id: project.id).delete_all
    TraceSpan.where(project_id: project.id).delete_all
    ApiKey.where(project_id: project.id).delete_all
    ProjectMembership.where(project_id: project.id).delete_all
    Project.where(id: project.id).delete_all
  end

  it "claims disjoint deliveries from the same project while another claim is uncommitted" do
    deliveries = 2.times.map { accept_event.telemetry_deliveries.first }

    TelemetryDelivery.transaction do
      first = TelemetryDelivery.claim_batch(limit: 1)
      second = in_connection { TelemetryDelivery.claim_batch(limit: 1) }

      expect(first.map(&:id) + second.map(&:id)).to match_array(deliveries.map(&:id))
      expect(first.map(&:id) & second.map(&:id)).to be_empty
    end
  end

  it "keeps a previously assigned retry batch intact when two claimers race" do
    deliveries = 2.times.map { accept_event.telemetry_deliveries.first }
    TelemetryDelivery.where(id: deliveries.map(&:id)).update_all(
      status: "retrying", attempts: 1, batch_key: "existing-retry-batch"
    )
    entered = Queue.new
    release = Queue.new
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
      sql = event.payload.fetch(:sql)
      next unless Thread.current[:contention_seed_gate] && sql.include?("LIMIT") &&
        sql.include?('INNER JOIN "projects"') && !sql.include?("FOR UPDATE")

      Thread.current[:contention_seed_gate] = false
      entered << true
      release.pop
    end
    threads = 2.times.map do
      connection_thread do
        Thread.current[:contention_seed_gate] = true
        TelemetryDelivery.claim_batch(limit: 1)
      ensure
        Thread.current[:contention_seed_gate] = nil
      end
    end
    Timeout.timeout(5) { 2.times { entered.pop } }
    2.times { release << true }
    batches = Timeout.timeout(5) { threads.map(&:value) }.reject(&:empty?)

    expect(batches.length).to eq(1)
    expect(batches.first.map(&:id)).to match_array(deliveries.map(&:id))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
    2.times { release << true } if release
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end
  end

  it "accepts telemetry while a ClickHouse write for the same project is in flight" do
    accept_event

    during_clickhouse_write do
      result = in_connection do
        ApplicationRecord.transaction do
          ApplicationRecord.connection.execute("SET LOCAL lock_timeout = '500ms'")
          accept_event
        end
      end
      expect(result).to be_persisted
    end
  end

  it "keeps the purge tombstone behind an in-flight ClickHouse write" do
    accept_event

    during_clickhouse_write do
      expect do
        in_connection do
          ApplicationRecord.transaction do
            ApplicationRecord.connection.execute("SET LOCAL lock_timeout = '150ms'")
            Logister::ProjectPurgeRequest.new(project: Project.find(project.id), enqueue: false).call
          end
        end
      end.to raise_error(ActiveRecord::LockWaitTimeout)
      expect(project.reload).not_to be_purge_pending
    end

    Logister::ProjectPurgeRequest.new(project: project.reload, enqueue: false).call
    expect(project.reload).to be_purge_pending
    expect(TelemetryDelivery.claim_batch(limit: 10)).to be_empty
  end

  it "allows another projector to finish a disjoint batch during a slow write" do
    2.times { accept_event }

    during_clickhouse_write do
      client = instance_double(Logister::ClickhouseClient, enabled?: true, insert_events!: nil)
      result = in_connection { Logister::TelemetryProjector.new(clickhouse_client: client).call(limit: 1) }
      expect(result).to have_attributes(claimed: 1, completed: 1)
      expect(client).to have_received(:insert_events!).once
    end
    expect(TelemetryProjectionWatermark.find_by!(project: project, signal: "log")).to be_complete
  end

  it "preserves exact counts and checksums when new buckets arrive concurrently in opposite orders" do
    client = instance_double(Logister::ClickhouseClient, write_enabled?: true)
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
    entered = Queue.new
    release = Queue.new
    allow(TelemetryProjectionWatermark).to receive(:record_accepted_batch!).and_wrap_original do |method, entries|
      entered << true
      release.pop
      method.call(entries)
    end
    batches = 2.times.map do |batch_index|
      Array.new(20) do |index|
        entry = event_entry
        entry.fetch(:attributes)[:occurred_at] = recorded_at - (index % 2).hours
        entry
      end.then { |entries| batch_index.zero? ? entries : entries.reverse }
    end
    threads = batches.map do |entries|
      connection_thread do
        Logister::TelemetryBatchAcceptance.new(
          project: Project.find(project.id), api_key: ApiKey.find(api_key.id), entries: entries
        ).call
      end
    end
    Timeout.timeout(5) { 2.times { entered.pop } }
    2.times { release << true }
    results = Timeout.timeout(5) { threads.map(&:value) }
    expect(results).to all(have_attributes(rejected: false))
    watermarks = TelemetryProjectionWatermark.where(project: project).order(:bucket_start_at)
    expect(watermarks.pluck(:accepted_count)).to eq([ 20, 20 ])
    batches.flatten.group_by { |entry| entry.fetch(:attributes).fetch(:occurred_at) }.each do |bucket, entries|
      checksum = entries.sum do |entry|
        TelemetryProjectionWatermark.identity_checksum(entry.fetch(:attributes).fetch(:uuid))
      end
      expect(watermarks.find { |watermark| watermark.bucket_start_at == bucket }.accepted_checksum).to eq(checksum)
    end
  ensure
    2.times { release << true } if release
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end
  end

  it "does not hold a bucket lock while the rest of an ingestion batch is persisted" do
    existing = accept_event.telemetry_deliveries.first
    existing.claim!
    entered = Queue.new
    release = Queue.new
    entries = 2.times.map { event_entry }
    client = instance_double(Logister::ClickhouseClient, write_enabled?: true)
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
    allow(Logister::TelemetryAcceptanceLedger).to receive(:accept!).and_wrap_original do |method, **args|
      result = method.call(**args)
      if args.fetch(:client_identifier) == entries.first.fetch(:attributes).fetch(:uuid)
        entered << true
        release.pop
      end
      result
    end

    batch = connection_thread do
      Logister::TelemetryBatchAcceptance.new(
        project: Project.find(project.id), api_key: ApiKey.find(api_key.id), entries: entries
      ).call
    end
    Timeout.timeout(5) { entered.pop }
    begin
      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute("SET LOCAL lock_timeout = '500ms'")
        expect(existing.mark_completed!).to be(true)
      end
    ensure
      release << true
      Timeout.timeout(5) { batch.join }
    end
    expect(batch.value).not_to be_rejected
    watermark = TelemetryProjectionWatermark.find_by!(project: project, signal: "log")
    expect(watermark).to have_attributes(accepted_count: 3, delivered_count: 1, complete_at: nil)
  ensure
    release << true if release
    batch&.kill if batch&.alive?
    batch&.join
  end

  private

  def event_entry
    {
      index: 0, type: "event", event_type: "log",
      attributes: {
        uuid: SecureRandom.uuid, event_type: "log", message: "contention test",
        occurred_at: recorded_at, context: { "environment" => "test" }
      }
    }
  end

  def accept_event
    IngestEventPersistence.new(
      project: Project.find(project.id), api_key: ApiKey.find(api_key.id),
      attributes: event_entry.fetch(:attributes), clickhouse_writable: true, installation: nil
    ).call.outbox_event
  end

  def connection_thread(&work)
    Thread.new do
      Thread.current.report_on_exception = false
      ActiveRecord::Base.connection_pool.with_connection { work.call }
    end
  end

  def in_connection(&work)
    thread = connection_thread(&work)
    Timeout.timeout(5) { thread.value }
  ensure
    thread&.kill if thread&.alive?
    thread&.join
  end

  def during_clickhouse_write
    entered = Queue.new
    release = Queue.new
    client = instance_double(Logister::ClickhouseClient, enabled?: true)
    allow(client).to receive(:insert_events!) do
      entered << true
      release.pop
    end
    projector = connection_thread { Logister::TelemetryProjector.new(clickhouse_client: client).call(limit: 1) }
    Timeout.timeout(5) { entered.pop }
    yield
  ensure
    release << true
    if projector
      begin
        Timeout.timeout(5) { projector.join }
        projector.value
      ensure
        projector.kill if projector.alive?
        projector.join
      end
    end
  end
end
