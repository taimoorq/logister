# frozen_string_literal: true

require "rails_helper"

RSpec.describe MobileEventEnrichments::Apple do
  let(:project) { create(:project, :ios) }
  let(:binary_uuid) { "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE" }
  let(:artifact) do
    create(
      :apple_symbol_artifact,
      project:,
      app_identifier: "com.acme.shop",
      version_code: "42",
      binary_uuid:,
      architecture: "arm64",
      status: "verified"
    )
  end
  let(:event) do
    create(
      :ingest_event,
      project:,
      context: {
        "platform" => "ios",
        "app" => { "identifier" => "com.acme.shop", "version_code" => "42" },
        "device" => { "architecture" => "arm64" },
        "exception" => {
          "threads" => [ {
            "id" => "crashed",
            "triggered" => true,
            "frames" => [ {
              "image" => "AcmeShop",
              "image_uuid" => binary_uuid,
              "address" => "0x100001234",
              "relative_address" => "0x1234",
              "application_frame" => true
            } ]
          } ],
          "binary_images" => [ {
            "name" => "AcmeShop",
            "uuid" => binary_uuid,
            "architecture" => "arm64",
            "base_address" => "0x100000000"
          } ]
        }
      }
    )
  end
  let(:derived_frame) do
    {
      "image" => "AcmeShop",
      "image_uuid" => binary_uuid,
      "address" => "0x100001234",
      "relative_address" => "0x1234",
      "base_address" => "0x100000000",
      "qualified_method" => "CheckoutStore.commit()",
      "symbol_identity" => "CheckoutStore.commit()",
      "method_name" => "CheckoutStore.commit()",
      "file" => "CheckoutStore.swift",
      "line_number" => 84,
      "application_frame" => true,
      "symbolicated" => true
    }
  end
  let(:symbolicator) { class_double(AppleSymbols::Symbolicator) }

  before do
    allow(symbolicator).to receive(:call).and_return(
      AppleSymbols::Symbolicator::Result.new(
        status: :complete,
        frames: [ derived_frame ],
        tool_name: "apple_atos",
        tool_version: "adapter-1; Xcode test",
        unresolved_count: 0
      )
    )
  end

  it "stores versioned derived symbols while preserving raw addresses and the immutable event" do
    original_context = event.context.deep_dup

    enrichment = described_class.call(project:, event:, artifacts: [ artifact ], symbolicator:)

    expect(enrichment).to have_attributes(
      platform: "ios",
      kind: "apple_symbolication",
      status: "complete",
      artifact_uuid: artifact.uuid,
      artifact_checksum_sha256: artifact.checksum_sha256,
      tool_name: "apple_atos",
      tool_version: "adapter-1; Xcode test"
    )
    expect(enrichment.data.dig("frames", 0)).to include(
      "image_uuid" => binary_uuid,
      "address" => "0x100001234",
      "qualified_method" => "CheckoutStore.commit()",
      "file" => "CheckoutStore.swift",
      "line_number" => 84
    )
    expect(event.reload.context).to eq(original_context)

    presenter = ProjectEvents::IosEventPresenter.new(event, enrichment:)
    expect(presenter.top_in_app_frame).to include(
      method_name: "CheckoutStore.commit()",
      file: "CheckoutStore.swift",
      line_number: 84,
      address: "0x100001234",
      symbolicated: true
    )
  end

  it "records an artifact match without invoking atos when the binary load address is absent" do
    event.context["exception"]["binary_images"][0].delete("base_address")
    event.save!

    enrichment = described_class.call(project:, event:, artifacts: [ artifact ], symbolicator:)

    expect(enrichment.status).to eq("artifact_matched")
    expect(enrichment.data).to include(
      "address_frame_count" => 1,
      "resolution_eligible_frame_count" => 0,
      "resolved_frame_count" => 0
    )
    expect(symbolicator).not_to have_received(:call)
  end

  it "reuses a current digest and reprocesses when the artifact checksum changes" do
    first = described_class.call(project:, event:, artifacts: [ artifact ], symbolicator:)
    first_digest = first.input_sha256
    expect(described_class.call(project:, event:, artifacts: [ artifact ], symbolicator:)).to eq(first)

    artifact.update!(checksum_sha256: Digest::SHA256.hexdigest("replacement"), processed_at: 1.minute.from_now)
    refreshed = described_class.call(project:, event:, artifacts: [ artifact ], symbolicator:)

    expect(refreshed.id).to eq(first.id)
    expect(refreshed.input_sha256).not_to eq(first_digest)
    expect(symbolicator).to have_received(:call).twice
  end
end
