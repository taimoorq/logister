# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppleSymbols::Symbolicator do
  it "resolves an exact UUID/architecture/load-address frame and stores no absolute source path" do
    artifact = build(
      :apple_symbol_artifact,
      binary_uuid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      architecture: "arm64"
    )
    runner_status = instance_double(Process::Status, success?: true)

    Dir.mktmpdir do |directory|
      binary = File.join(directory, "AcmeShop.dSYM", "Contents", "Resources", "DWARF", "AcmeShop")
      FileUtils.mkdir_p(File.dirname(binary))
      FileUtils.touch(binary)
      allow(AppleSymbols::ArchiveWorkspace).to receive(:open).with(artifact:).and_yield(directory)
      allow(Open3).to receive(:capture2e) do |*command|
        case command.first
        when "dwarfdump"
          [ "UUID: #{artifact.binary_uuid} (arm64) #{binary}\n", runner_status ]
        when "atos"
          expect(command).to include("-l", "0x100000000", "0x100001234")
          [ "CheckoutStore.commit() (in AcmeShop) (/private/build/CheckoutStore.swift:84)\n", runner_status ]
        when "xcodebuild"
          [ "Xcode 99.0\nBuild version TEST\n", runner_status ]
        end
      end
      resolver = described_class.new(
        artifact:,
        frames: [ {
          image: "AcmeShop",
          image_uuid: artifact.binary_uuid,
          address: "0x100001234",
          relative_address: "0x1234",
          base_address: "0x100000000"
        } ]
      )
      allow(resolver).to receive(:tooling_available?).and_return(true)

      result = resolver.call

      expect(result.status).to eq(:complete)
      expect(result.frames.sole).to include(
        "qualified_method" => "CheckoutStore.commit()",
        "file" => "CheckoutStore.swift",
        "line_number" => 84,
        "address" => "0x100001234",
        "symbolicated" => true
      )
      expect(result.frames.to_json).not_to include("/private/build")
      expect(result.tool_version).to include("adapter-1", "Xcode 99.0")
    end
  end
end
