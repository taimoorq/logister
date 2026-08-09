# frozen_string_literal: true

require "digest"

module MobileEventEnrichments
  class Apple
    MATCHER_NAME = "logister_apple_symbol_matcher"
    MATCHER_VERSION = "1"
    LOOKUP_ARTIFACTS = Object.new.freeze
    MAX_FRAMES = AppleSymbols::Symbolicator::MAX_FRAMES

    def self.call(...)
      new(...).call
    end

    attr_reader :project, :event, :presenter, :artifacts, :symbolicator, :now

    def initialize(
      project:,
      event:,
      presenter: ProjectEvents::IosEventPresenter.new(event),
      artifacts: LOOKUP_ARTIFACTS,
      symbolicator: AppleSymbols::Symbolicator,
      now: Time.current
    )
      @project = project
      @event = event
      @presenter = presenter
      @artifacts = artifacts.equal?(LOOKUP_ARTIFACTS) ? build_artifacts : Array(artifacts)
      @symbolicator = symbolicator
      @now = now
    end

    def call
      record = project.mobile_event_enrichments.find_or_initialize_by(event_uuid: event.uuid, kind: "apple_symbolication")
      digest = input_sha256
      return record if record.persisted? && record.input_sha256 == digest && record.status != "failed"

      coverage = AppleSymbolCoverage.call(project:, event:, presenter:, artifacts:)
      results = symbolicate_frames
      attributes = enrichment_attributes(coverage, results, digest)
      record.assign_attributes(attributes)
      record.save!
      record
    rescue StandardError => error
      record ||= project.mobile_event_enrichments.find_or_initialize_by(event_uuid: event.uuid, kind: "apple_symbolication")
      record.assign_attributes(failure_attributes(error, digest || input_sha256))
      record.save!
      raise
    end

    private

    def build_artifacts
      app = presenter.app_details
      return [] if app[:bundle_identifier].blank? || app[:version_code].blank?

      project.apple_symbol_artifacts.where(
        app_identifier: app[:bundle_identifier],
        version_code: app[:version_code].to_s
      ).to_a
    end

    def address_frames
      @address_frames ||= begin
        images_by_uuid = presenter.binary_images.index_by { |image| normalize_uuid(image[:uuid]) }
        images_by_name = presenter.binary_images.index_by { |image| image[:name].to_s }
        fallback_architecture = presenter.device_details[:architecture]

        presenter.all_frames.filter_map do |frame|
          next unless frame[:application_frame]
          next unless frame[:address].present? || frame[:relative_address].present?
          next if callable_symbol?(frame[:method_name])

          image = images_by_uuid[normalize_uuid(frame[:image_uuid])] || images_by_name[frame[:image].to_s]
          {
            image: frame[:image],
            image_uuid: normalize_uuid(frame[:image_uuid] || image&.dig(:uuid)),
            architecture: (image&.dig(:architecture) || fallback_architecture).to_s.downcase.presence,
            base_address: image&.dig(:base_address),
            address: frame[:address],
            relative_address: frame[:relative_address]
          }.compact
        end.uniq.first(MAX_FRAMES)
      end
    end

    def target_frames
      @target_frames ||= address_frames.select do |frame|
        frame[:base_address].present? && frame[:image_uuid].present? && frame[:architecture].present?
      end
    end

    def symbolicate_frames
      target_frames.group_by { |frame| matching_artifact(frame) }.filter_map do |artifact, frames|
        next unless artifact

        symbolicator.call(artifact:, frames:)
      end
    end

    def matching_artifact(frame)
      artifacts.find do |artifact|
        artifact.verified? &&
          artifact.binary_uuid == normalize_uuid(frame[:image_uuid]) &&
          artifact.architecture == frame[:architecture]
      end
    end

    def enrichment_attributes(coverage, results, digest)
      references = artifact_references
      derived_frames = results.flat_map(&:frames)
      {
        event_occurred_at: event.occurred_at,
        platform: "ios",
        status: enrichment_status(coverage, results, derived_frames),
        input_sha256: digest,
        artifact_type: references.any? ? "AppleSymbolArtifact" : nil,
        artifact_uuid: references.one? ? references.first.fetch("uuid") : nil,
        artifact_checksum_sha256: aggregate_artifact_checksum(references),
        tool_name: results.map(&:tool_name).uniq.join(", ").presence || MATCHER_NAME,
        tool_version: results.map(&:tool_version).uniq.join(", ").presence || MATCHER_VERSION,
        data: {
          "schema_version" => 1,
          "frames" => derived_frames,
          "artifacts" => references,
          "address_frame_count" => address_frames.size,
          "resolution_eligible_frame_count" => target_frames.size,
          "resolved_frame_count" => derived_frames.size,
          "unresolved_frame_count" => address_frames.size - derived_frames.size
        },
        processing_error: nil,
        processed_at: now
      }
    end

    def enrichment_status(coverage, results, derived_frames)
      return "complete" if address_frames.empty?
      return "partial" if derived_frames.any? && (derived_frames.size < address_frames.size || coverage.status == :partial_coverage)
      return "complete" if derived_frames.size == address_frames.size
      return "artifact_matched" if results.any? || coverage.status == :artifact_matched

      {
        partial_coverage: "partial",
        verification_pending: "verification_pending",
        verification_failed: "verification_failed",
        missing: "missing",
        build_unknown: "build_unknown",
        symbols_included: "complete",
        not_applicable: "complete"
      }.fetch(coverage.status)
    end

    def artifact_references
      artifacts.select(&:verified?).map do |artifact|
        {
          "uuid" => artifact.uuid,
          "binary_uuid" => artifact.binary_uuid,
          "architecture" => artifact.architecture,
          "checksum_sha256" => artifact.checksum_sha256
        }
      end.sort_by { |reference| reference.values_at("binary_uuid", "architecture") }
    end

    def aggregate_artifact_checksum(references)
      return if references.empty?
      return references.first.fetch("checksum_sha256") if references.one?

      Digest::SHA256.hexdigest(references.to_json)
    end

    def input_sha256
      @input_sha256 ||= Digest::SHA256.hexdigest(
        {
          tool: [ MATCHER_NAME, MATCHER_VERSION, AppleSymbols::Symbolicator::ADAPTER_VERSION ],
          event_uuid: event.uuid,
          app: presenter.app_details.slice(:bundle_identifier, :version_code),
          frames: address_frames,
          artifacts: artifacts.map do |artifact|
            [ artifact.uuid, artifact.checksum_sha256, artifact.status, artifact.processed_at&.utc&.iso8601(6) ]
          end.sort
        }.to_json
      )
    end

    def failure_attributes(error, digest)
      references = artifact_references
      {
        event_occurred_at: event.occurred_at,
        platform: "ios",
        status: "failed",
        input_sha256: digest,
        artifact_type: references.any? ? "AppleSymbolArtifact" : nil,
        artifact_uuid: references.one? ? references.first.fetch("uuid") : nil,
        artifact_checksum_sha256: aggregate_artifact_checksum(references),
        tool_name: MATCHER_NAME,
        tool_version: MATCHER_VERSION,
        data: {
          "schema_version" => 1,
          "artifacts" => references,
          "address_frame_count" => address_frames.size,
          "resolution_eligible_frame_count" => target_frames.size
        },
        processing_error: "#{error.class}: #{error.message}".first(2_000),
        processed_at: now
      }
    end

    def callable_symbol?(value)
      symbol = value.to_s.strip
      symbol.present? && !symbol.match?(/\A(?:0x[0-9a-f]+|\+?\s*\d+)\z/i)
    end

    def normalize_uuid(value)
      value.to_s.delete("{}").upcase.presence
    end
  end
end
