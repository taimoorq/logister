# frozen_string_literal: true

require "rails_helper"
require "open3"

RSpec.describe "Apple symbolication toolchain integration" do
  REQUIRED_TOOLS = %w[clang dsymutil dwarfdump atos nm otool zip unzip].freeze

  it "resolves a real Mach-O address from a generated dSYM archive" do
    skip "Apple command-line tools are unavailable" unless RUBY_PLATFORM.include?("darwin") && REQUIRED_TOOLS.all? { |tool| system("which", tool, out: File::NULL) }

    Dir.mktmpdir("logister-symbol-integration-") do |directory|
      source = Rails.root.join("spec/fixtures/apple_symbols/logister_fixture.c").to_s
      binary = File.join(directory, "LogisterFixture")
      dsym = "#{binary}.dSYM"
      archive = File.join(directory, "LogisterFixture.dSYM.zip")
      run!("clang", "-g", "-O0", source, "-o", binary)
      run!("dsymutil", binary, "-o", dsym)

      uuid_output = run!("dwarfdump", "--uuid", binary)
      uuid_match = /UUID: (?<uuid>[0-9A-F-]+) \((?<architecture>[^)]+)\)/i.match(uuid_output)
      expect(uuid_match).to be_present
      symbol_output = run!("nm", "-n", binary)
      symbol_match = /\A(?<address>[0-9a-f]+)\s+T\s+_logister_fixture_target\s*$/i.match(symbol_output.lines.find { |line| line.include?("_logister_fixture_target") }.to_s)
      expect(symbol_match).to be_present
      load_commands = run!("otool", "-l", binary)
      base_match = /segname __TEXT.*?vmaddr (?<address>0x[0-9a-f]+)/im.match(load_commands)
      expect(base_match).to be_present
      run!("zip", "-qry", archive, File.basename(dsym), chdir: directory)

      storage_root = File.join(directory, "archive-storage")
      locator = InstanceConfiguration::ArchiveService.with_generation_id("service" => "local", "root" => storage_root)
      storage_key = "symbols/LogisterFixture.dSYM.zip"
      service = InstanceConfiguration::ArchiveService.build(locator:)
      File.open(archive, "rb") { |io| service.upload(storage_key, io) }
      artifact = create(
        :apple_symbol_artifact,
        binary_uuid: uuid_match[:uuid],
        architecture: uuid_match[:architecture],
        checksum_sha256: Digest::SHA256.file(archive).hexdigest,
        byte_size: File.size(archive),
        storage_key:,
        status: "verified",
        metadata: { "storage_locator" => locator }
      )

      result = AppleSymbols::Symbolicator.call(
        artifact:,
        frames: [ {
          image: "LogisterFixture",
          image_uuid: uuid_match[:uuid],
          address: "0x#{symbol_match[:address]}",
          base_address: base_match[:address]
        } ]
      )

      expect(result.status).to eq(:complete)
      expect(result.frames.sole).to include(
        "image_uuid" => uuid_match[:uuid].upcase,
        "application_frame" => true,
        "symbolicated" => true
      )
      expect(result.frames.sole.fetch("qualified_method")).to include("logister_fixture_target")
    end
  end

  def run!(*command, chdir: nil)
    arguments = command.dup
    arguments << { chdir: } if chdir
    output, status = Open3.capture2e(*arguments)
    raise "#{command.join(' ')} failed: #{output}" unless status.success?

    output
  end
end
