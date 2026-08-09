# frozen_string_literal: true

require "digest"
require "set"

module Logister
  module ProjectPurgeAdapters
    class Archives
      ObjectEntry = Data.define(:key, :locator, :version_id)
      DEFAULT_WRITE_QUIESCENCE = 2.minutes
      DEFAULT_FINAL_VERIFICATION_DELAY = 30.seconds

      def initialize(project_purge:, storage_service: nil, now: Time.current)
        @project_purge = project_purge
        @injected_storage_service = storage_service
        @services = {}
        @now = now
      end

      def call
        project = Project.find_by(id: @project_purge.source_project_id)
        unless project
          return awaiting_external(
            "Project control-plane rows disappeared before archive keys and versions were verified"
          )
        end

        quiet_at = write_quiet_at
        if quiet_at && @now < quiet_at
          return awaiting_external(
            "Waiting for ambiguous pre-tombstone object uploads to quiesce",
            retry_at: quiet_at,
            phase: "write_quiescence"
          )
        end

        entries = object_entries(project)
        unresolved = entries.select { |entry| entry.locator.blank? }
        if unresolved.any? && !legacy_storage_attested_current?
          return awaiting_external(
            "#{unresolved.size} legacy objects have no immutable storage locator; reconnect/migrate them or attest that they remain in the current store"
          )
        end

        normalized = entries.map do |entry|
          locator = entry.locator.presence || InstanceConfiguration::ArchiveService.current_locator
          ObjectEntry.new(key: entry.key, locator: locator, version_id: entry.version_id)
        end
        preflight_services!(normalized)

        deleted = 0
        already_absent = 0
        versions_deleted = 0
        normalized.each do |entry|
          service = service_for(entry.locator)
          existed = object_or_version_exists?(service, entry.key)
          outcome = InstanceConfiguration::ArchiveService.delete_all_versions!(service, entry.key)
          existed ? deleted += 1 : already_absent += 1
          versions_deleted += outcome.fetch(:versions_deleted)
        end

        keys = normalized.map(&:key).uniq
        summary = {
          status: "completed",
          objects: keys.size,
          deleted_objects: deleted,
          already_absent_objects: already_absent,
          versions_deleted: versions_deleted,
          storage_generations: normalized.filter_map { |entry| entry.locator["generation_id"] }.uniq.sort,
          key_set_sha256: Digest::SHA256.hexdigest(keys.sort.join("\n")),
          verified_absent: true
        }
        if durable_step? && !final_verification_pass?
          return awaiting_external(
            "Initial object deletion completed; a delayed second version sweep is required",
            retry_at: @now + final_verification_delay,
            phase: "mutation_complete",
            deletion_summary: summary.except(:status)
          )
        end

        mark_archive_objects_deleted!(project, keys)
        summary
      rescue ArgumentError, KeyError => error
        awaiting_external("A recorded archive storage generation cannot be resolved: #{error.message}")
      rescue Aws::S3::Errors::ServiceError => error
        awaiting_external("A recorded archive storage generation cannot be reached or version-verified: #{error.message}")
      end

      private

      def object_entries(project)
        entries = TelemetryArchiveObject
          .joins(:telemetry_archive)
          .where(telemetry_archives: { project_id: project.id })
          .pluck(:object_key, :storage_locator, :object_version_id)
          .map { |key, locator, version_id| ObjectEntry.new(key: key, locator: locator, version_id: version_id) }

        recorded_keys = entries.map(&:key).to_set
        project.telemetry_archives.find_each do |archive|
          locator = archive.lifecycle_metadata&.dig("storage_locator")
          archive.object_keys.each do |key|
            next if recorded_keys.include?(key)

            entries << ObjectEntry.new(key: key, locator: locator, version_id: nil)
          end
        end
        project.apple_symbol_artifacts.find_each do |artifact|
          metadata = artifact.metadata.is_a?(Hash) ? artifact.metadata : {}
          entries << ObjectEntry.new(
            key: artifact.storage_key,
            locator: metadata["storage_locator"],
            version_id: metadata["object_version_id"]
          )
        end
        entries.reject { |entry| entry.key.blank? }.uniq { |entry| [ entry.key, entry.locator ] }
      end

      def preflight_services!(entries)
        entries.each { |entry| service_for(entry.locator) }
      end

      def service_for(locator)
        return @injected_storage_service if @injected_storage_service

        generation = locator.fetch("generation_id")
        @services[generation] ||= InstanceConfiguration::ArchiveService.build(locator: locator)
      end

      def object_or_version_exists?(service, key)
        return service.exist?(key) unless InstanceConfiguration::ArchiveService.s3_service?(service)

        response = service.client.client.list_object_versions(bucket: service.bucket.name, prefix: key)
        (response.versions.to_a + response.delete_markers.to_a).any? { |entry| entry.key == key }
      end

      def legacy_storage_attested_current?
        ActiveModel::Type::Boolean.new.cast(
          ENV.fetch("LOGISTER_ATTEST_LEGACY_ARCHIVE_STORAGE_CURRENT", "false")
        )
      end

      def write_quiet_at
        return unless @project_purge.respond_to?(:tombstoned_at) && @project_purge.tombstoned_at

        @project_purge.tombstoned_at + ENV.fetch(
          "LOGISTER_PROJECT_PURGE_WRITE_QUIESCENCE_SECONDS",
          DEFAULT_WRITE_QUIESCENCE.to_i
        ).to_i.seconds
      end

      def final_verification_delay
        ENV.fetch(
          "LOGISTER_PROJECT_PURGE_FINAL_VERIFICATION_SECONDS",
          DEFAULT_FINAL_VERIFICATION_DELAY.to_i
        ).to_i.seconds
      end

      def durable_step?
        @project_purge.respond_to?(:steps)
      end

      def final_verification_pass?
        return false unless durable_step?

        @project_purge.steps.find_by(store_name: "archives")&.result&.fetch("phase", nil) == "mutation_complete"
      end

      def awaiting_external(reason, retry_at: nil, **details)
        {
          status: "awaiting_external",
          reason: reason,
          retry_at: retry_at&.utc&.iso8601,
          remediation_gate: "LOGISTER_ATTEST_LEGACY_ARCHIVE_STORAGE_CURRENT",
          verified_absent: false
        }.merge(details).compact
      end

      def mark_archive_objects_deleted!(project, keys)
        now = Time.current
        TelemetryArchiveObject
          .where(telemetry_archive_id: project.telemetry_archives.select(:id), object_key: keys)
          .update_all(status: "deleted", deleted_at: now, updated_at: now)
        project.telemetry_archives.find_each do |archive|
          object_records = archive.object_records
          next if object_records.exists? && object_records.where.not(status: "deleted").exists?
          next unless (archive.object_keys - keys).empty?

          archive.update_columns(status: "deleted", updated_at: now)
        end
      end
    end
  end
end
