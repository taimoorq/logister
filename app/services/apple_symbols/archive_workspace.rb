# frozen_string_literal: true

require "find"
require "open3"
require "tmpdir"

module AppleSymbols
  class ArchiveWorkspace
    class Error < StandardError; end

    MAX_EXPANDED_BYTES = 2.gigabytes
    MAX_FILES = 20_000

    def self.open(artifact:, &block)
      new(artifact:).open(&block)
    end

    attr_reader :artifact

    def initialize(artifact:)
      @artifact = artifact
    end

    def open
      Dir.mktmpdir("logister-dsym-") do |directory|
        archive = File.join(directory, "artifact.zip")
        download!(archive)
        entries = archive_entries(archive)
        validate_entries!(entries)
        validate_expanded_size!(archive)
        extract!(archive, directory)
        validate_extracted_files!(directory)
        yield directory
      end
    end

    private

    def download!(path)
      locator = artifact.metadata.is_a?(Hash) ? artifact.metadata["storage_locator"] : nil
      service = InstanceConfiguration::ArchiveService.build(locator: locator)
      File.open(path, "wb") do |file|
        service.download(artifact.storage_key) { |chunk| file.write(chunk) }
      end
    end

    def archive_entries(archive)
      output, status = Open3.capture2e("unzip", "-Z1", archive)
      raise Error, "Unable to inspect dSYM archive: #{output}" unless status.success?

      output.lines
    end

    def extract!(archive, directory)
      output, status = Open3.capture2e("unzip", "-qq", archive, "-d", directory)
      raise Error, "Unable to extract dSYM archive: #{output}" unless status.success?
    end

    def validate_entries!(entries)
      raise Error, "dSYM archive contains too many files" if entries.size > MAX_FILES

      unsafe = entries.find { |entry| entry.start_with?("/", "\\") || entry.split(/[\\\/]/).include?("..") }
      raise Error, "dSYM archive contains an unsafe path" if unsafe
    end

    def validate_expanded_size!(archive)
      listing, status = Open3.capture2e("unzip", "-Z", "-l", archive)
      raise Error, "Unable to read dSYM archive sizes: #{listing}" unless status.success?

      match = /(\d+)\s+files?,\s+(\d+)\s+bytes uncompressed/i.match(listing)
      raise Error, "Unable to determine dSYM expanded size" unless match
      if match[2].to_i > MAX_EXPANDED_BYTES
        raise Error, "dSYM archive expands beyond #{MAX_EXPANDED_BYTES / 1.gigabyte} GB"
      end
    end

    def validate_extracted_files!(directory)
      unsafe = Find.find(directory).find { |path| path != directory && File.symlink?(path) }
      raise Error, "dSYM archive contains a symbolic link" if unsafe
    end
  end
end
