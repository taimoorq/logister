# frozen_string_literal: true

require "open3"
require "tmpdir"
require "find"

class AppleSymbolArtifactProcessingJob < ApplicationJob
  queue_as :default
  MAX_EXPANDED_BYTES = 2.gigabytes

  def perform(artifact_id)
    artifact = AppleSymbolArtifact.find_by(id: artifact_id)
    return unless artifact

    claimed = artifact.with_lock do
      next false unless artifact.processable?

      artifact.update!(status: "processing", processing_error: nil)
      true
    end
    return unless claimed
    unless tooling_available?
      artifact.update!(
        status: "awaiting_tooling",
        processing_error: "Apple dwarfdump and unzip tooling are unavailable on this worker.",
        metadata: artifact.metadata.merge("tooling_checked_at" => Time.current.utc.iso8601)
      )
      return
    end

    manifest = inspect_archive(artifact)
    expected = [ artifact.binary_uuid, artifact.architecture ]
    unless manifest.any? { |entry| entry.values_at("uuid", "architecture") == expected }
      raise "Archive does not contain UUID #{artifact.binary_uuid} for #{artifact.architecture}"
    end

    artifact.update!(
      status: "ready",
      processing_error: nil,
      processed_at: Time.current,
      metadata: artifact.metadata.merge("uuid_manifest" => manifest, "tooling" => "dwarfdump")
    )
  rescue StandardError => error
    artifact&.update_columns(status: "failed", processing_error: error.message.to_s.first(2_000), updated_at: Time.current)
    raise
  end

  private

  def tooling_available?
    executable?("unzip") && executable?("dwarfdump")
  end

  def executable?(name)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |path| File.executable?(File.join(path, name)) }
  end

  def inspect_archive(artifact)
    Dir.mktmpdir("logister-dsym-") do |directory|
      archive = File.join(directory, "artifact.zip")
      File.open(archive, "wb") do |file|
        InstanceConfiguration::ArchiveService.build.download(artifact.storage_key) { |chunk| file.write(chunk) }
      end
      entries, status = Open3.capture2e("unzip", "-Z1", archive)
      raise "Unable to inspect dSYM archive: #{entries}" unless status.success?
      validate_entries!(entries.lines)
      validate_expanded_size!(archive)
      output, status = Open3.capture2e("unzip", "-qq", archive, "-d", directory)
      raise "Unable to extract dSYM archive: #{output}" unless status.success?
      validate_extracted_files!(directory)

      Dir.glob(File.join(directory, "**", "*.dSYM")).flat_map do |bundle|
        dwarfdump, dump_status = Open3.capture2e("dwarfdump", "--uuid", bundle)
        raise "Unable to inspect #{File.basename(bundle)}: #{dwarfdump}" unless dump_status.success?

        dwarfdump.lines.filter_map do |line|
          match = /UUID: (?<uuid>[0-9A-F-]+) \((?<architecture>[^)]+)\)/i.match(line)
          { "uuid" => match[:uuid].upcase, "architecture" => match[:architecture].downcase, "bundle" => File.basename(bundle) } if match
        end
      end
    end
  end

  def validate_entries!(entries)
    raise "dSYM archive contains too many files" if entries.size > 20_000
    unsafe = entries.find { |entry| entry.start_with?("/", "\\") || entry.split(/[\\\/]/).include?("..") }
    raise "dSYM archive contains an unsafe path" if unsafe
  end

  def validate_expanded_size!(archive)
    listing, status = Open3.capture2e("unzip", "-Z", "-l", archive)
    raise "Unable to read dSYM archive sizes: #{listing}" unless status.success?

    match = /(\d+)\s+files?,\s+(\d+)\s+bytes uncompressed/i.match(listing)
    raise "Unable to determine dSYM expanded size" unless match
    raise "dSYM archive expands beyond #{MAX_EXPANDED_BYTES / 1.gigabyte} GB" if match[2].to_i > MAX_EXPANDED_BYTES
  end

  def validate_extracted_files!(directory)
    unsafe = Find.find(directory).find { |path| path != directory && File.symlink?(path) }
    raise "dSYM archive contains a symbolic link" if unsafe
  end
end
