# frozen_string_literal: true

module Logister
  class TelemetryArchiveRestore
    class RestoreError < StandardError; end

    def initialize(archive:, storage_service: nil, dry_run: false)
      @archive = archive
      locator = archive.lifecycle_metadata&.dig("storage_locator")
      @storage_service = storage_service || InstanceConfiguration::ArchiveService.build(locator: locator)
      @dry_run = dry_run
    end

    def call
      raise RestoreError, "Archive must have a verified manifest before restore" unless @archive.verified?
      raise RestoreError, "Archive project no longer exists" unless @archive.project

      return perform_restore if @dry_run

      Project.transaction(requires_new: true) do
        project = Project.lock.find_by(id: @archive.project_id)
        if project.nil? || project.purge_pending?
          raise RestoreError, "Project purge is pending; archive restore is disabled"
        end

        perform_restore
      end
    rescue StandardError => error
      restore_failed!(error) unless @dry_run
      raise error if error.is_a?(RestoreError)

      raise RestoreError, "Archive restore failed: #{error.class}: #{error.message}"
    end

    private

    def perform_restore
      TelemetryArchiveInspector.new(
        archive: @archive,
        storage_service: @storage_service,
        persist: false
      ).call

      result = { archive_id: @archive.id, restored: 0, skipped: 0, restored_derived: 0, dry_run: @dry_run }
      @archive.update!(status: "restoring", error_message: nil) unless @dry_run

      replay.each_row do |row, _object_record|
        attributes = restore_attributes(row)
        if source_exists?(attributes)
          result[:restored_derived] += restore_derived_evidence(row, attributes)
          result[:skipped] += 1
          next
        end

        validate_references!(attributes)
        model.create!(attributes) unless @dry_run
        result[:restored_derived] += restore_derived_evidence(row, attributes)
        result[:restored] += 1
      end

      complete_restore!(result) unless @dry_run
      result
    end

    def replay
      @replay ||= TelemetryArchiveReplay.new(
        archive: @archive,
        storage_service: @storage_service,
        verify: false
      )
    end

    def model
      @archive.record_type == "ingest_events" ? IngestEvent : TraceSpan
    end

    def restore_attributes(row)
      attributes = row.fetch("attributes").slice(*model.column_names)
      attributes["project_id"] = @archive.project_id
      if model == IngestEvent
        attributes["api_key_id"] = row.dig("restore_references", "api_key_id") || attributes["api_key_id"]
      end

      if model == IngestEvent && attributes["error_group_id"].present? &&
          !ErrorGroup.exists?(id: attributes["error_group_id"], project_id: @archive.project_id)
        attributes["error_group_id"] = nil
      end
      attributes
    rescue KeyError
      raise RestoreError, "Archive row is missing attributes"
    end

    def source_exists?(attributes)
      if model == IngestEvent
        IngestEvent.for_partition_reference(
          id: attributes.fetch("id"),
          occurred_at: attributes.fetch("occurred_at")
        ).where(project_id: @archive.project_id).exists?
      else
        TraceSpan.where(project_id: @archive.project_id, id: attributes.fetch("id")).exists? ||
          TraceSpan.where(
            project_id: @archive.project_id,
            trace_id: attributes.fetch("trace_id"),
            span_id: attributes.fetch("span_id")
          ).exists?
      end
    end

    def validate_references!(attributes)
      api_key_id = attributes["api_key_id"]
      return if ApiKey.exists?(id: api_key_id, project_id: @archive.project_id)

      raise RestoreError, "Archive row references missing API key #{api_key_id.inspect}"
    end

    def restore_derived_evidence(row, source_attributes)
      return 0 unless model == IngestEvent

      Array(row["derived_evidence"]).count do |derived|
        next false unless derived.is_a?(Hash)
        next true if @dry_run

        enrichment = @archive.project.mobile_event_enrichments.find_or_initialize_by(
          event_uuid: source_attributes.fetch("uuid"),
          kind: derived.fetch("kind")
        )
        enrichment.assign_attributes(
          derived.slice(
            "uuid", "event_occurred_at", "platform", "status", "input_sha256",
            "artifact_type", "artifact_uuid", "artifact_checksum_sha256",
            "tool_name", "tool_version", "data", "processed_at"
          )
        )
        enrichment.event_occurred_at ||= source_attributes.fetch("occurred_at")
        enrichment.save!
        true
      end
    rescue KeyError => error
      raise RestoreError, "Archive derived evidence is incomplete: #{error.message}"
    end

    def complete_restore!(result)
      now = Time.current
      metadata = @archive.lifecycle_metadata.is_a?(Hash) ? @archive.lifecycle_metadata.dup : {}
      metadata["last_restore"] = result.merge("completed_at" => now.utc.iso8601).as_json
      @archive.update!(
        status: "restored",
        restored_at: now,
        lifecycle_metadata: metadata,
        error_message: nil
      )
    end

    def restore_failed!(error)
      return unless @archive&.persisted?

      metadata = @archive.lifecycle_metadata.is_a?(Hash) ? @archive.lifecycle_metadata.dup : {}
      metadata["last_restore_error"] = {
        "class" => error.class.name,
        "message" => error.message,
        "at" => Time.current.utc.iso8601
      }
      @archive.update_columns(
        status: "completed",
        lifecycle_metadata: metadata,
        error_message: "#{error.class}: #{error.message}",
        updated_at: Time.current
      )
    rescue StandardError
      nil
    end
  end
end
