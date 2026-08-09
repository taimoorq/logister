# frozen_string_literal: true

require "rails_helper"

RSpec.describe IngestEventsPartitionMaintenanceJob, type: :job do
  it "runs partition maintenance on the isolated maintenance queue" do
    partitioning = instance_double(
      Logister::IngestEventsPartitioning,
      ensure_future_partitions: { blocked_partitions: [] }
    )
    allow(Logister::IngestEventsPartitioning).to receive(:new).and_return(partitioning)

    described_class.perform_now

    expect(described_class.queue_name).to eq("maintenance")
    expect(partitioning).to have_received(:ensure_future_partitions)
  end
end
