# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppleSymbolArtifactProcessingJob, type: :job do
  include ActiveJob::TestHelper

  it "records an explicit awaiting-tooling state when the worker cannot inspect Apple symbols" do
    artifact = create(:apple_symbol_artifact)
    allow_any_instance_of(described_class).to receive(:tooling_available?).and_return(false)

    described_class.perform_now(artifact.id)

    expect(artifact.reload).to have_attributes(
      status: "awaiting_tooling",
      processing_error: include("dwarfdump")
    )
  end

  it "calls UUID inspection verified and queues coverage refresh without claiming symbolication" do
    artifact = create(:apple_symbol_artifact)
    allow_any_instance_of(described_class).to receive(:tooling_available?).and_return(true)
    allow_any_instance_of(described_class).to receive(:inspect_archive).and_return([
      { "uuid" => artifact.binary_uuid, "architecture" => artifact.architecture, "bundle" => "AcmeShop.dSYM" }
    ])

    expect do
      described_class.perform_now(artifact.id)
    end.to have_enqueued_job(MobileArtifactCoverageRefreshJob).with(artifact.project_id, "ios")

    expect(artifact.reload).to have_attributes(status: "verified", processing_error: nil)
    expect(artifact.metadata).to include("tooling" => "dwarfdump")
  end
end
