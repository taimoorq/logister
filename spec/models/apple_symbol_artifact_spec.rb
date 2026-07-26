# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppleSymbolArtifact do
  it "normalizes UUID identity and enforces iOS ownership" do
    artifact = build(
      :apple_symbol_artifact,
      binary_uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      architecture: "ARM64"
    )

    expect(artifact).to be_valid
    expect(artifact.binary_uuid).to eq("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
    expect(artifact.architecture).to eq("arm64")

    artifact.project = create(:project, :android)
    expect(artifact).not_to be_valid
    expect(artifact.errors[:project]).to include("must be an iOS project")
  end

  it "does not allow duplicate UUID, architecture, and checksum identity within a project" do
    existing = create(:apple_symbol_artifact)
    duplicate = build(
      :apple_symbol_artifact,
      project: existing.project,
      binary_uuid: existing.binary_uuid,
      architecture: existing.architecture,
      checksum_sha256: existing.checksum_sha256
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:checksum_sha256]).to be_present
  end
end
