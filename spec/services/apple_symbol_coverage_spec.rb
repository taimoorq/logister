# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppleSymbolCoverage do
  let(:project) { create(:project, :ios) }
  let(:api_key) { create(:api_key, project: project, user: project.user) }

  def event_with_frame(symbol: nil, binary_uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
    create(
      :ingest_event,
      project: project,
      api_key: api_key,
      context: {
        "platform" => "ios",
        "app" => { "identifier" => "com.acme.shop", "version_name" => "4.2.0", "version_code" => "310" },
        "device" => { "architecture" => "arm64" },
        "symbolication" => { "status" => "symbolicated" },
        "exception" => {
          "stacktrace" => [ {
            "image" => "AcmeShop",
            "image_uuid" => binary_uuid,
            "address" => "0x1004a1290",
            "symbol" => symbol,
            "application_frame" => true
          } ]
        }
      }
    )
  end

  it "derives included symbols from frames instead of trusting client status" do
    event = event_with_frame(symbol: "CheckoutViewModel.submit(_:)")
    event.context["symbolication"]["status"] = "missing"
    event.save!

    expect(described_class.call(project: project, event: event)).to have_attributes(
      status: :symbols_included,
      label: "Symbols included"
    )
  end

  it "distinguishes a verified exact artifact match from completed symbolication" do
    event = event_with_frame
    artifact = create(
      :apple_symbol_artifact,
      project: project,
      app_identifier: "com.acme.shop",
      version_code: "310",
      binary_uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      architecture: "arm64",
      status: "verified"
    )

    coverage = described_class.call(project: project, event: event)

    expect(coverage.status).to eq(:artifact_matched)
    expect(coverage.label).to eq("Verified dSYM matched")
    expect(coverage.matched_artifacts).to eq([ artifact ])
    expect(described_class.call(project: project, event: event, artifacts: [ artifact ]).status).to eq(:artifact_matched)
  end

  it "keeps uploaded and failed artifact verification separate from coverage" do
    event = event_with_frame
    artifact = create(
      :apple_symbol_artifact,
      project: project,
      app_identifier: "com.acme.shop",
      version_code: "310",
      binary_uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      architecture: "arm64",
      status: "uploaded"
    )

    expect(described_class.call(project: project, event: event).status).to eq(:verification_pending)

    artifact.update!(status: "failed")
    expect(described_class.call(project: project, event: event).status).to eq(:verification_failed)
  end

  it "distinguishes completed server symbolication from artifact eligibility" do
    event = event_with_frame
    artifact = create(
      :apple_symbol_artifact,
      project: project,
      app_identifier: "com.acme.shop",
      version_code: "310",
      binary_uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      architecture: "arm64",
      status: "verified"
    )
    enrichment = create(
      :mobile_event_enrichment,
      :apple_symbolication,
      project:,
      event_uuid: event.uuid,
      event_occurred_at: event.occurred_at,
      artifact_type: "AppleSymbolArtifact",
      artifact_uuid: artifact.uuid,
      artifact_checksum_sha256: artifact.checksum_sha256,
      data: {
        "schema_version" => 1,
        "artifacts" => [ {
          "uuid" => artifact.uuid,
          "binary_uuid" => artifact.binary_uuid,
          "architecture" => artifact.architecture,
          "checksum_sha256" => artifact.checksum_sha256
        } ],
        "frames" => [ { "image_uuid" => artifact.binary_uuid, "address" => "0x1004a1290", "method_name" => "CheckoutStore.commit()" } ],
        "resolved_frame_count" => 1
      }
    )

    coverage = described_class.call(project:, event:, artifacts: [ artifact ], enrichment:)

    expect(coverage).to have_attributes(status: :symbolicated, label: "Frames symbolicated", enrichment:)
  end
end
