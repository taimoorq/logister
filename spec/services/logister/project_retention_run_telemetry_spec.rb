# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ProjectRetentionRunTelemetry do
  it "emits correlated progress without policy snapshots, payloads, keys, or error messages" do
    run = create(
      :project_retention_run,
      status: "retrying",
      phase: "uploading",
      current_scope: "hot_events",
      attempts: 2,
      fence_version: 3,
      objects_total: 10,
      objects_completed: 4,
      rows_total: 10_000,
      rows_completed: 4_000,
      last_error_message: "private object key"
    )
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(described_class::EVENT_NAME) do |*arguments|
      events << ActiveSupport::Notifications::Event.new(*arguments).payload
    end

    payload = described_class.emit(
      event: "retry_scheduled",
      run: run,
      error_class: "Timeout::Error",
      wait_seconds: 5,
      source_payload: "must not escape"
    )

    expect(payload).to include(
      event: "retry_scheduled",
      run_id: run.id,
      project_id: run.project_id,
      status: "retrying",
      phase: "uploading",
      objects_completed: 4,
      error_class: "Timeout::Error",
      wait_seconds: 5
    )
    expect(payload).not_to include(:source_payload, :last_error_message, :policy_snapshot, :cutoff_snapshot, :result)
    expect(events).to contain_exactly(payload)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
