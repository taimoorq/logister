# frozen_string_literal: true

require "rails_helper"

RSpec.describe MobileEventEnrichments::Android do
  let(:project) { create(:project, :android) }
  let(:mapping_content) { Rails.root.join("spec/fixtures/files/android_mapping.txt").binread }
  let(:mapping) do
    create(
      :android_mapping_file,
      project: project,
      version_code: "42",
      content: mapping_content,
      byte_size: mapping_content.bytesize,
      checksum_sha256: Digest::SHA256.hexdigest(mapping_content)
    )
  end
  let(:event) do
    create(
      :ingest_event,
      project: project,
      context: {
        "platform" => "android",
        "app" => { "package_name" => "com.acme.shop", "version_code" => "42" },
        "error" => { "mechanism" => "unhandled_exception" },
        "exception" => {
          "type" => "java.lang.IllegalStateException",
          "message" => "private order 123",
          "stacktrace" => [ {
            "class_name" => "a",
            "method_name" => "b",
            "file_name" => "SourceFile.java",
            "line_number" => 3,
            "in_app" => true
          } ]
        }
      }
    )
  end

  it "stores versioned derived frames while preserving the immutable raw event" do
    original_context = event.context.deep_dup

    enrichment = described_class.call(project: project, event: event, mapping_file: mapping)

    expect(enrichment).to have_attributes(
      platform: "android",
      kind: "android_mapping",
      status: "complete",
      artifact_uuid: mapping.uuid,
      artifact_checksum_sha256: mapping.checksum_sha256,
      tool_name: "logister_android_mapper",
      tool_version: "1"
    )
    expect(enrichment.data.dig("frames", 0)).to include(
      "qualified_method" => "com.acme.shop.storage.CartStore.write",
      "file" => "CartStore.java",
      "line_number" => 21,
      "deobfuscated" => true,
      "obfuscated_class_name" => "a"
    )
    expect(enrichment.data.to_json).not_to include("private order 123", "raw")
    expect(event.reload.context).to eq(original_context)
  end

  it "reuses a current digest and refreshes when the artifact checksum changes" do
    first = described_class.call(project: project, event: event, mapping_file: mapping)
    first_digest = first.input_sha256
    expect(described_class.call(project: project, event: event, mapping_file: mapping)).to eq(first)

    replacement = mapping_content.sub("CartStore", "CheckoutStore")
    mapping.update!(content: replacement, byte_size: replacement.bytesize, checksum_sha256: Digest::SHA256.hexdigest(replacement))
    refreshed = described_class.call(project: project, event: event, mapping_file: mapping)

    expect(refreshed.id).to eq(first.id)
    expect(refreshed.input_sha256).not_to eq(first_digest)
    expect(refreshed.data.dig("frames", 0, "qualified_method")).to include("CheckoutStore.write")
  end

  it "serves current derived frames without running the mapper again" do
    enrichment = described_class.call(project: project, event: event, mapping_file: mapping)
    allow(AndroidStacktraceMapper).to receive(:new).and_raise("mapper should not run")

    resolution = AndroidMappingResolution.call(
      project: project,
      event: event,
      mapping_file: mapping,
      enrichment: enrichment
    )

    expect(resolution).to be_mapped
    expect(resolution.frames.first[:qualified_method]).to eq("com.acme.shop.storage.CartStore.write")
  end
end
