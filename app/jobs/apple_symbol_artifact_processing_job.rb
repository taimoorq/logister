# frozen_string_literal: true

require "open3"

class AppleSymbolArtifactProcessingJob < ApplicationJob
  queue_as :symbols

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
      status: "verified",
      processing_error: nil,
      processed_at: Time.current,
      metadata: artifact.metadata.merge("uuid_manifest" => manifest, "tooling" => "dwarfdump")
    )
    MobileArtifactCoverageRefreshJob.perform_later(artifact.project_id, "ios")
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
    AppleSymbols::ArchiveWorkspace.open(artifact:) do |directory|
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
end
