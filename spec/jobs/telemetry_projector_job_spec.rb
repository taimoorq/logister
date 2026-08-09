# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryProjectorJob, type: :job do
  include ActiveJob::TestHelper

  let(:redis) { instance_double(Redis) }

  before do
    allow(described_class).to receive(:queue_adapter_name).and_return("sidekiq")
    allow(Sidekiq).to receive(:redis).and_yield(redis)
  end

  it "coalesces intake wakeups behind a short Sidekiq Redis lease" do
    allow(redis).to receive(:set).and_return("OK", nil)

    expect {
      2.times { described_class.wake! }
    }.to have_enqueued_job(described_class).exactly(:once)

    expect(redis).to have_received(:set).twice.with(
      described_class::WAKE_KEY,
      kind_of(String),
      nx: true,
      ex: described_class::WAKE_TTL.to_i
    )
  end

  it "falls back to an uncoalesced enqueue when the wake lease is unavailable" do
    allow(Sidekiq).to receive(:redis).and_raise(StandardError, "Redis unavailable")
    allow(Rails.logger).to receive(:warn)

    expect {
      expect(described_class.wake!).to be(true)
    }.to have_enqueued_job(described_class).exactly(:once)

    expect(Rails.logger).to have_received(:warn).with(/wake_coalescing_error.*Redis unavailable/)
  end

  it "never lets Redis and enqueue failures escape into telemetry acceptance" do
    allow(Sidekiq).to receive(:redis).and_raise(StandardError, "Redis unavailable")
    allow(described_class).to receive(:perform_later).and_raise(StandardError, "enqueue unavailable")
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)

    result = nil
    expect { result = described_class.wake! }.not_to raise_error
    expect(result).to be(false)
    expect(Rails.logger).to have_received(:error).with(/wake_enqueue_error.*enqueue unavailable/)
  end

  it "reuses one persistent ClickHouse client for the whole drain and closes it" do
    client = instance_double(Logister::ClickhouseClient, close: nil)
    projector = instance_double(Logister::TelemetryProjector)
    working = Logister::TelemetryProjector::Result.new(1, 1, 0, 0)
    drained = Logister::TelemetryProjector::Result.new(0, 0, 0, 0)
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
    allow(Logister::TelemetryProjector).to receive(:new)
      .with(clickhouse_client: client)
      .and_return(projector)
    allow(projector).to receive(:call).and_return(working, drained)
    job = described_class.new
    allow(job).to receive(:reschedule_sidekiq_recurring_job)

    job.perform(max_batches: 3)

    expect(Logister::ClickhouseClient).to have_received(:new).once
    expect(Logister::TelemetryProjector).to have_received(:new).once
    expect(projector).to have_received(:call).twice
    expect(client).to have_received(:close).once
  end

  it "closes the persistent ClickHouse client when projection raises" do
    client = instance_double(Logister::ClickhouseClient, close: nil)
    projector = instance_double(Logister::TelemetryProjector)
    allow(Logister::ClickhouseClient).to receive(:new).and_return(client)
    allow(Logister::TelemetryProjector).to receive(:new).and_return(projector)
    allow(projector).to receive(:call).and_raise(StandardError, "projection failed")
    job = described_class.new
    allow(job).to receive(:reschedule_sidekiq_recurring_job)

    expect { job.perform }.to raise_error(StandardError, "projection failed")
    expect(client).to have_received(:close).once
  end
end
