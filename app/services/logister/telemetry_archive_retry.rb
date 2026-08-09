# frozen_string_literal: true

module Logister
  class TelemetryArchiveRetry
    def initialize(archive:, storage_service: nil)
      @archive = archive
      @storage_service = storage_service
    end

    def call
      unless @archive.manifest_version.to_i >= 2
        raise TelemetryArchiveExporter::Error, "Legacy manifests cannot be retried safely"
      end
      if @archive.status.in?(%w[deleted deleting])
        raise TelemetryArchiveExporter::Error, "Deleted archive manifests cannot be retried"
      end

      metadata = @archive.lifecycle_metadata.is_a?(Hash) ? @archive.lifecycle_metadata : {}
      TelemetryArchiveExporter.new(
        archive: @archive,
        record_type: @archive.record_type,
        project: @archive.project,
        scope: @archive.scope,
        before: @archive.before_at,
        after: @archive.after_at,
        event_types: metadata["event_types"],
        batch_size: metadata["batch_size"],
        prefix: metadata["prefix"],
        selection: metadata["selection"],
        protect_incomplete_deliveries: metadata["protect_incomplete_deliveries"],
        storage_service: @storage_service
      ).call
    end
  end
end
