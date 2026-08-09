# frozen_string_literal: true

require "digest"

module MobileEventEnrichments
  class Android
    TOOL_NAME = "logister_android_mapper"
    TOOL_VERSION = "1"
    LOOKUP_MAPPING = Object.new.freeze
    FRAME_KEYS = %i[
      class_name qualified_method method_name file line_number column_number
      application_frame obfuscated_class_name obfuscated_method_name
      obfuscated_line_number deobfuscated
    ].freeze

    def self.call(...)
      new(...).call
    end

    attr_reader :project, :event, :presenter, :mapping_file, :now

    def initialize(project:, event:, presenter: ProjectEvents::AndroidEventPresenter.new(event), mapping_file: LOOKUP_MAPPING, now: Time.current)
      @project = project
      @event = event
      @presenter = presenter
      @mapping_file = mapping_file.equal?(LOOKUP_MAPPING) ? matching_mapping : mapping_file
      @now = now
    end

    def call
      resolution = AndroidMappingResolution.call(
        project: project,
        event: event,
        presenter: presenter,
        mapping_file: mapping_file
      )
      attributes = enrichment_attributes(resolution)
      record = project.mobile_event_enrichments.find_or_initialize_by(event_uuid: event.uuid, kind: "android_mapping")
      return record if record.persisted? && record.input_sha256 == attributes.fetch(:input_sha256)

      record.assign_attributes(attributes)
      record.save!
      record
    rescue StandardError => error
      record ||= project.mobile_event_enrichments.find_or_initialize_by(event_uuid: event.uuid, kind: "android_mapping")
      record.assign_attributes(
        event_occurred_at: event.occurred_at,
        platform: "android",
        status: "failed",
        input_sha256: input_sha256,
        artifact_type: mapping_file.present? ? "AndroidMappingFile" : nil,
        artifact_uuid: mapping_file&.uuid,
        artifact_checksum_sha256: mapping_file&.checksum_sha256,
        tool_name: TOOL_NAME,
        tool_version: TOOL_VERSION,
        data: {},
        processing_error: "#{error.class}: #{error.message}".first(2_000),
        processed_at: now
      )
      record.save!
      raise
    end

    private

    def matching_mapping
      app = presenter.app_details
      return if app[:package_name].blank? || app[:version_code].blank?

      project.android_mapping_files.find_by(package_name: app[:package_name], version_code: app[:version_code].to_s)
    end

    def enrichment_attributes(resolution)
      {
        event_occurred_at: event.occurred_at,
        platform: "android",
        status: enrichment_status(resolution.status),
        input_sha256: input_sha256,
        artifact_type: mapping_file.present? ? "AndroidMappingFile" : nil,
        artifact_uuid: mapping_file&.uuid,
        artifact_checksum_sha256: mapping_file&.checksum_sha256,
        tool_name: TOOL_NAME,
        tool_version: TOOL_VERSION,
        data: derived_data(resolution),
        processing_error: nil,
        processed_at: now
      }
    end

    def enrichment_status(status)
      {
        mapped: "complete",
        mapping_matched: "artifact_matched",
        missing: "missing",
        build_unknown: "build_unknown"
      }.fetch(status)
    end

    def derived_data(resolution)
      return {} unless %i[mapped mapping_matched].include?(resolution.status)

      {
        "schema_version" => 1,
        "frames" => safe_frames(resolution.frames),
        "cause_chain" => resolution.cause_chain.map do |entry|
          {
            "depth" => entry[:depth],
            "type" => entry[:type],
            "frames" => safe_frames(entry[:frames])
          }.compact
        end
      }
    end

    def safe_frames(frames)
      Array(frames).map { |frame| frame.slice(*FRAME_KEYS).stringify_keys.compact }
    end

    def input_sha256
      @input_sha256 ||= Digest::SHA256.hexdigest(
        {
          tool: [ TOOL_NAME, TOOL_VERSION ],
          event_uuid: event.uuid,
          artifact_checksum: mapping_file&.checksum_sha256,
          app: presenter.app_details.slice(:package_name, :version_code),
          frames: presenter.all_frames.map { |frame| frame.slice(:class_name, :method_name, :file, :line_number) }
        }.to_json
      )
    end
  end
end
