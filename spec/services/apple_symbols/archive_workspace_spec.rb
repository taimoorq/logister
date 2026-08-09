# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppleSymbols::ArchiveWorkspace do
  let(:locator) { { "driver" => "s3", "generation_id" => "symbols-v1" } }
  let(:artifact) { build(:apple_symbol_artifact, metadata: { "storage_locator" => locator }) }
  let(:workspace) { described_class.new(artifact:) }

  it "rejects traversal and absolute paths through the shared verification/symbolication guard" do
    expect { workspace.send(:validate_entries!, [ "../escape" ]) }
      .to raise_error(described_class::Error, /unsafe path/)
    expect { workspace.send(:validate_entries!, [ "/absolute" ]) }
      .to raise_error(described_class::Error, /unsafe path/)
  end

  it "downloads from the artifact's immutable storage generation" do
    service = double("archive service")
    allow(InstanceConfiguration::ArchiveService).to receive(:build).with(locator:).and_return(service)
    allow(service).to receive(:download).with(artifact.storage_key).and_yield("PK\x03\x04".b)

    Dir.mktmpdir do |directory|
      path = File.join(directory, "artifact.zip")
      workspace.send(:download!, path)
      expect(File.binread(path)).to eq("PK\x03\x04".b)
    end
  end
end
