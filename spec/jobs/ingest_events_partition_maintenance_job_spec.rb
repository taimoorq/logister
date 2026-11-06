# frozen_string_literal: true

require "rails_helper"

RSpec.describe IngestEventsPartitionMaintenanceJob, type: :job do
  it "creates future partitions, retires empty expired ones, and flags compaction candidates" do
    candidate = {
      name: "public.ingest_events_partitioned_2026_05",
      total_bytes: 3_100_000_000,
      estimated_reclaimable_bytes: 3_080_000_000
    }
    partitioning = instance_double(
      Logister::IngestEventsPartitioning,
      ensure_future_partitions: { blocked_partitions: [] },
      retire_expired_partitions: { retired_partitions: [], skipped_partitions: [] },
      compaction_candidates: [ candidate ]
    )
    allow(Logister::IngestEventsPartitioning).to receive(:new).and_return(partitioning)
    allow(Rails.logger).to receive(:warn)

    described_class.perform_now

    expect(described_class.queue_name).to eq("maintenance")
    expect(partitioning).to have_received(:ensure_future_partitions)
    expect(partitioning).to have_received(:retire_expired_partitions)
    expect(Rails.logger).to have_received(:warn).with(include("need operator compaction", "ingest_events_partitioned_2026_05"))
  end
end
