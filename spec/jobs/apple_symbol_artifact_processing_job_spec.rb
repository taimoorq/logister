# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppleSymbolArtifactProcessingJob, type: :job do
  it "records an explicit awaiting-tooling state when the worker cannot inspect Apple symbols" do
    artifact = create(:apple_symbol_artifact)
    allow_any_instance_of(described_class).to receive(:tooling_available?).and_return(false)

    described_class.perform_now(artifact.id)

    expect(artifact.reload).to have_attributes(
      status: "awaiting_tooling",
      processing_error: include("dwarfdump")
    )
  end
end
