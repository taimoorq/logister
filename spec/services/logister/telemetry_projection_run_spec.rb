# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::TelemetryProjectionRun, type: :model do
  let(:now) { Time.current.change(usec: 0) }
  let(:project) { create(:project) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }
  let(:session) { instance_double(Logister::TelemetryProjectorAdmission::Session, heartbeat: true) }
  let(:client) { instance_double(Logister::ClickhouseClient, enabled?: true, insert_event_payload!: nil) }
  let(:run) { described_class.new(session: session, clock: -> { @clock }) }

  around do |example|
    previous = ENV["LOGISTER_BATCHED_PROJECTION"]
    ENV["LOGISTER_BATCHED_PROJECTION"] = "true"
    example.run
  ensure
    previous.nil? ? ENV.delete("LOGISTER_BATCHED_PROJECTION") : ENV["LOGISTER_BATCHED_PROJECTION"] = previous
  end

  before do
    @clock = 0
    allow(Logister::ClickhouseFailureReporter).to receive(:report_event_failure)
  end

  it "finishes one synchronous unit and refunds wholly unstarted claims when the deadline is reached" do
    deliveries = 12.times.map { accept_delivery(type: "error") }
    allow(ErrorGroupingService).to receive(:call).and_wrap_original do |method, *args, **kwargs|
      method.call(*args, **kwargs)
      @clock = 26
    end

    result = projector.call(run: run)

    expect(result).to have_attributes(claimed: 10, completed: 1)
    expect(deliveries.first.reload).to have_attributes(status: "completed", attempts: 1)
    expect(deliveries.drop(1).map(&:reload)).to all(have_attributes(status: "pending", attempts: 0, lease_token: nil))
    expect(ErrorGroupingService).to have_received(:call).once
  end

  it "does not claim anything once the run expires" do
    delivery = accept_delivery
    run
    @clock = 25
    expect(projector.call(run: run)).to have_attributes(claimed: 0)
    expect(delivery.reload).to have_attributes(status: "pending", attempts: 0)
  end

  it "retains exact payload identity and refunds the attempt when ownership is lost before the external write" do
    delivery = accept_delivery
    allow(session).to receive(:heartbeat).with(force: true).and_return(false)

    10.times do
      expect(projector.call(run: run)).to have_attributes(claimed: 1, completed: 0, retried: 0)
      expect(delivery.reload).to have_attributes(status: "pending", attempts: 0)
    end
    batch = TelemetryProjectionBatch.sole
    expect(delivery.batch_key).to eq(batch.batch_key)
    expect(client).not_to have_received(:insert_event_payload!)
    allow(session).to receive(:heartbeat).with(force: true).and_return(true)
    expect(projector.call(run: run)).to have_attributes(completed: 1)
    expect(client).to have_received(:insert_event_payload!).with(batch.payload, deduplication_token: batch.batch_key, gzip: true)
  end

  it "finishes an in-flight insert and exact ACK after the cooperative deadline" do
    delivery = accept_delivery
    allow(client).to receive(:insert_event_payload!) { @clock = 26 }
    expect(projector.call(run: run)).to have_attributes(completed: 1)
    expect(delivery.reload).to be_completed
    expect(TelemetryProjectionWatermark.find_by!(project: project)).to be_complete
  end

  it "renews the entire owned delivery lease before an external write" do
    delivery = accept_delivery
    allow(TelemetryProjectionBatch).to receive(:prepare!).and_wrap_original do |method, **args|
      method.call(**args).tap do
        TelemetryDelivery.where(id: delivery.id).update_all(lease_expires_at: now + 1.second)
      end
    end
    allow(client).to receive(:insert_event_payload!) do
      expect(delivery.reload.lease_expires_at).to eq(now + TelemetryDelivery::DEFAULT_LEASE)
    end
    expect(projector.call(run: run)).to have_attributes(completed: 1)
  end

  it "never sends under expired or replaced PostgreSQL ownership" do
    delivery = accept_delivery
    replacement_token = SecureRandom.uuid
    allow(TelemetryProjectionBatch).to receive(:prepare!).and_wrap_original do |method, **args|
      method.call(**args).tap do
        TelemetryDelivery.where(id: delivery.id).update_all(lease_token: replacement_token, lease_expires_at: now)
      end
    end
    expect(projector.call(run: run)).to have_attributes(completed: 0)
    expect(client).not_to have_received(:insert_event_payload!)
    expect(delivery.reload).to have_attributes(status: "processing", lease_token: replacement_token, attempts: 1)
  end

  it "does not resurrect even a matching expired token or partially renew a mixed-ownership group" do
    2.times { accept_delivery }
    deliveries = TelemetryDelivery.claim_batch(limit: 2, now: now)
    before = deliveries.map(&:lease_expires_at)
    deliveries.last.update_columns(lease_expires_at: now)
    expect do
      TelemetryDelivery.renew_batch_lease!(deliveries, at: now)
    end.to raise_error(TelemetryDelivery::BatchOwnershipLost)
    expect(deliveries.first.reload.lease_expires_at).to eq(before.first)
    expect(deliveries.last.reload.lease_expires_at).to eq(now)
    TelemetryDelivery.release_unstarted_batch!([ deliveries.last ], at: now)
    expect(deliveries.last.reload).to have_attributes(status: "processing", attempts: 1)
  end

  it "retains a whole persisted retry body despite a smaller requested fresh batch limit" do
    12.times { accept_delivery }
    allow(client).to receive(:insert_event_payload!).and_raise(Logister::ClickhouseClient::Error, "response lost")
    expect(projector.call(run: run)).to have_attributes(retried: 12)
    batch = TelemetryProjectionBatch.sole
    allow(client).to receive(:insert_event_payload!).and_return(nil)
    expect(projector(at: now + 3.seconds).call(limit: 1, run: run)).to have_attributes(claimed: 12, completed: 12)
    expect(client).to have_received(:insert_event_payload!).with(batch.payload, deduplication_token: batch.batch_key, gzip: true).twice
  end

  it "leaves attempted rows leased when failure bookkeeping reaches the deadline" do
    delivery = accept_delivery
    allow(client).to receive(:insert_event_payload!) do
      @clock = 26
      raise Logister::ClickhouseClient::Error, "response lost"
    end
    expect(projector.call(run: run)).to have_attributes(claimed: 1, completed: 0, retried: 0)
    expect(delivery.reload).to have_attributes(status: "processing", attempts: 1)
    expect(TelemetryProjectionBatch.sole.delivery_ids).to eq([ delivery.id ])
  end

  it "sets bounded PostgreSQL waits without an outer transaction and restores the connection after failure" do
    connection = ActiveRecord::Base.connection
    original = settings(connection)
    transaction_depth = connection.open_transactions
    expect do
      run.with_database_limits do
        expect(settings(connection)).to eq([ "5s", "1s" ])
        expect(connection.open_transactions).to eq(transaction_depth)
        raise "unit failed"
      end
    end.to raise_error("unit failed")
    expect(settings(connection)).to eq(original)
  end

  it "preserves stricter existing PostgreSQL limits" do
    connection = ActiveRecord::Base.connection
    original = settings(connection)
    connection.execute("SET statement_timeout = '500ms'")
    connection.execute("SET lock_timeout = '100ms'")
    run.with_database_limits { expect(settings(connection)).to eq([ "500ms", "100ms" ]) }
    expect(settings(connection)).to eq([ "500ms", "100ms" ])
  ensure
    connection.execute("SET statement_timeout = #{connection.quote(original[0])}")
    connection.execute("SET lock_timeout = #{connection.quote(original[1])}")
  end

  private

  def accept_delivery(type: "log")
    result = IngestEventPersistence.new(project: project, api_key: api_key,
      attributes: { uuid: SecureRandom.uuid, event_type: type, message: "run boundary", occurred_at: now },
      clickhouse_writable: type == "log", installation: nil).call
    result.outbox_event.telemetry_deliveries.find_by!(destination: type == "log" ? "clickhouse_event" : "error_grouping")
      .tap { |delivery| delivery.update_columns(available_at: now) }
  end

  def projector(at: now)
    Logister::TelemetryProjector.new(clickhouse_client: client, now: -> { at })
  end

  def settings(connection)
    %w[statement_timeout lock_timeout].map { |name| connection.select_value("SHOW #{name}") }
  end
end
