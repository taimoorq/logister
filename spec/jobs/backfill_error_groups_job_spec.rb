# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackfillErrorGroupsJob, type: :job do
  include ActiveJob::TestHelper

  let(:project) { projects(:one) }
  let(:api_key) { api_keys(:one) }

  it "enqueues with default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "groups ungrouped error events via ErrorGroupingService" do
    event = IngestEvent.create!(
      project: project,
      api_key: api_key,
      event_type: :error,
      message: "Backfill spec error",
      fingerprint: "backfill-fp-#{SecureRandom.hex(4)}",
      occurred_at: Time.current
    )
    expect(event.reload.error_group_id).to be_nil

    perform_enqueued_jobs do
      described_class.perform_now
    end

    event.reload
    expect(event.error_group_id).to be_present
    expect(event.error_group).to be_present
    expect(event.error_group.fingerprint).to eq(event.fingerprint)
  end

  it "does not re-group events that already have error_group_id" do
    event = IngestEvent.create!(
      project: project,
      api_key: api_key,
      event_type: :error,
      message: "Already grouped",
      fingerprint: "already-#{SecureRandom.hex(4)}",
      occurred_at: Time.current
    )
    ErrorGroupingService.call(event)
    group_id = event.reload.error_group_id
    expect(group_id).to be_present

    perform_enqueued_jobs do
      described_class.perform_now
    end

    expect(event.reload.error_group_id).to eq(group_id)
  end

  it "processes only error-type events" do
    metric_event = IngestEvent.create!(
      project: project,
      api_key: api_key,
      event_type: :metric,
      message: "Metric only",
      fingerprint: "metric-only",
      occurred_at: Time.current
    )
    expect(metric_event.error_group_id).to be_nil

    perform_enqueued_jobs do
      described_class.perform_now
    end

    expect(metric_event.reload.error_group_id).to be_nil
  end
end
