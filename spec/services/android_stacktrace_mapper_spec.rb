# frozen_string_literal: true

require "rails_helper"

RSpec.describe AndroidStacktraceMapper do
  let(:mapping_file) do
    build(
      :android_mapping_file,
      content: Rails.root.join("spec/fixtures/files/android_mapping.txt").binread,
      byte_size: Rails.root.join("spec/fixtures/files/android_mapping.txt").size,
      checksum_sha256: Digest::SHA256.file(Rails.root.join("spec/fixtures/files/android_mapping.txt")).hexdigest
    )
  end

  it "retraces a matching obfuscated class, method, and line" do
    frame = {
      class_name: "a",
      method_name: "b",
      qualified_method: "a.b",
      file: "SourceFile.java",
      line_number: 3,
      application_frame: true
    }

    mapped = described_class.new(mapping_file).map_frame(frame)

    expect(mapped).to include(
      class_name: "com.acme.shop.storage.CartStore",
      method_name: "write",
      qualified_method: "com.acme.shop.storage.CartStore.write",
      file: "CartStore.java",
      line_number: 21,
      deobfuscated: true,
      obfuscated_class_name: "a"
    )
  end

  it "leaves frames not covered by this release mapping unchanged" do
    frame = { class_name: "android.app.Activity", method_name: "onCreate", file: "Activity.java", line_number: 10 }
    expect(described_class.new(mapping_file).map_frame(frame)).to eq(frame)
  end
end
