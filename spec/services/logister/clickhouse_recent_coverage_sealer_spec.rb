# frozen_string_literal: true

require "rails_helper"

RSpec.describe Logister::ClickhouseRecentCoverageSealer do
  it "reconciles a bounded overlap of closed hours for every event and span signal" do
    client = instance_double(Logister::ClickhouseClient, enabled?: true)
    result = double(status: "verified")
    reconciler = class_double(Logister::ClickhouseBackfillWatermarkReconciler, call: result)

    results = described_class.call(
      project_id: 42,
      client: client,
      closed_before: Time.utc(2026, 8, 8, 12, 30),
      watermark_reconciler: reconciler
    )

    expect(results.length).to eq(12)
    expect(reconciler).to have_received(:call).exactly(12).times
    expect(reconciler).to have_received(:call).with(
      client: client,
      project_id: 42,
      signal: "span",
      bucket_start_at: Time.utc(2026, 8, 8, 11),
      source_complete: true
    )
    expect(reconciler).to have_received(:call).with(
      client: client,
      project_id: 42,
      signal: "metric",
      bucket_start_at: Time.utc(2026, 8, 8, 10),
      source_complete: true
    )
  end
end
