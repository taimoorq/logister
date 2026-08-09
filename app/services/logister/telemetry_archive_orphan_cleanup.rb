# frozen_string_literal: true

module Logister
  class TelemetryArchiveOrphanCleanup
    class CleanupError < StandardError; end

    def initialize(candidate_keys:, prefix: InstanceConfiguration.value("archive_storage.prefix"),
                   storage_service: nil, dry_run: true)
      @candidate_keys = Array(candidate_keys).compact_blank.map { |key| key.to_s.delete_prefix("/") }.uniq
      @prefix = prefix.to_s.delete_prefix("/").delete_suffix("/")
      @storage_service = storage_service || InstanceConfiguration::ArchiveService.build
      @dry_run = dry_run
    end

    def call
      raise CleanupError, "An archive prefix is required for orphan cleanup" if @prefix.blank?

      scoped_candidates = @candidate_keys.select { |key| key.start_with?("#{@prefix}/") }
      referenced = referenced_keys(scoped_candidates)
      orphans = scoped_candidates - referenced
      deleted = []

      orphans.each do |key|
        next if @dry_run

        @storage_service.delete(key)
        if @storage_service.respond_to?(:exist?) && @storage_service.exist?(key)
          raise CleanupError, "Archive object still exists after delete: #{key}"
        end
        deleted << key
      end

      {
        prefix: @prefix,
        candidates: scoped_candidates.size,
        referenced: referenced,
        orphans: orphans,
        deleted: deleted,
        dry_run: @dry_run,
        enumeration: "candidate_keys must come from an operator-approved storage inventory"
      }
    end

    private

    def referenced_keys(candidates)
      return [] if candidates.empty?

      exact = TelemetryArchiveObject.where(object_key: candidates).pluck(:object_key)
      remaining = candidates - exact
      return exact if remaining.empty?

      legacy = []
      TelemetryArchive.find_each do |archive|
        legacy.concat(archive.object_keys & remaining)
      end
      (exact + legacy).uniq
    end
  end
end
