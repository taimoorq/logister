# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::TelemetryBatchAcceptance, type: :model do
  let!(:project) { create(:project) }
  let!(:api_key) { create(:api_key, project: project, user: project.user) }

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

  it "resolves invariant configuration once and avoids per-envelope savepoints" do
    entries = 3.times.map do |index|
      event_entry(
        format("11111111-1111-4111-8111-%012d", index),
        message: "event #{index}"
      )
    end
    clickhouse = instance_double(Logister::ClickhouseClient, write_enabled?: false)
    expect(Logister::ClickhouseClient).to receive(:new).once.and_return(clickhouse)
    expect(Installation).to receive(:current_if_available).once.and_return(nil)
    expect(Logister::TelemetryIdentityLock).to receive(:acquire!).once.and_call_original
    statements = capture_sql do
      @result = described_class.new(project: project, api_key: api_key, entries: entries).call
    end

    expect(@result).not_to be_rejected
    expect(@result.entries).to all(include(accepted: true, duplicate: false))
    expect_single_batch_transaction(statements)
    expect(statements.grep(/pg_advisory_xact_lock/i).length).to eq(1)
  end

  it "bulk-loads existing identities and accepts a whole-batch retry" do
    entries = [
      event_entry("22222222-2222-4222-8222-222222222222", message: "one"),
      event_entry("33333333-3333-4333-8333-333333333333", message: "two")
    ]
    first = described_class.new(project: project, api_key: api_key, entries: entries).call
    expect(first).not_to be_rejected

    statements = capture_sql do
      @retry = described_class.new(project: project, api_key: api_key, entries: entries).call
    end

    key_selects = statements.select do |sql|
      sql.match?(/\ASELECT/i) && sql.include?('FROM "telemetry_idempotency_keys"')
    end
    expect(@retry).not_to be_rejected
    expect(@retry.entries).to all(include(accepted: true, duplicate: true))
    expect(@retry.outbox_events.map(&:id)).to match_array(first.outbox_events.map(&:id))
    expect(key_selects.length).to eq(1)
    expect_single_batch_transaction(statements)
  end

  it "serializes a repeated identity within one batch without a second source row" do
    uuid = "44444444-4444-4444-8444-444444444444"
    entries = [ event_entry(uuid, message: "first"), event_entry(uuid, message: "retry payload") ]

    result = described_class.new(project: project, api_key: api_key, entries: entries).call

    expect(result).not_to be_rejected
    expect(result.entries.pluck(:duplicate)).to eq([ false, true ])
    expect(project.ingest_events.where(uuid: uuid).count).to eq(1)
    expect(TelemetryIdempotencyKey.where(project: project, client_identifier: uuid).count).to eq(1)
    expect(result.outbox_events.length).to eq(1)
  end

  private

  def event_entry(uuid, message:)
    {
      index: 0,
      type: "event",
      event_type: "log",
      attributes: {
        uuid: uuid,
        event_type: "log",
        message: message,
        occurred_at: Time.current,
        context: { "environment" => "test" }
      }.with_indifferent_access
    }
  end

  def capture_sql
    statements = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      statements << payload.fetch(:sql) unless payload[:name] == "SCHEMA" || payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    statements
  end

  def expect_single_batch_transaction(statements)
    # Transactional fixtures wrap the example in a non-joinable transaction,
    # so the batch's one required all-or-nothing boundary is represented as a
    # savepoint. There must not be another savepoint for each envelope.
    expect(statements.grep(/\ASAVEPOINT\b/i).length).to eq(1)
    expect(statements.grep(/\ARELEASE SAVEPOINT\b/i).length).to eq(1)
    expect(statements.grep(/\AROLLBACK TO SAVEPOINT\b/i)).to be_empty
  end
end
