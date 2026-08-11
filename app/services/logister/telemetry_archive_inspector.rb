# frozen_string_literal: true

require "digest"
require "json"
require "stringio"
require "zlib"

module Logister
  class TelemetryArchiveInspector
    class VerificationError < StandardError; end

    def initialize(archive:, storage_service: nil, persist: false, object_limit: nil, work_fence: nil)
      @archive = archive
      locator = archive.lifecycle_metadata&.dig("storage_locator") if archive.respond_to?(:lifecycle_metadata)
      @storage_service = storage_service || InstanceConfiguration::ArchiveService.build(locator: locator)
      @persist = persist
      @object_limit = object_limit.to_i if object_limit.to_i.positive?
      @work_fence = work_fence
    end

    def call
      return inspect_legacy_archive if @archive.manifest_version.to_i < 2

      manifest_totals = verify_manifest_metadata!
      return inspect_and_persist_objects(manifest_totals) if @persist

      totals = {
        rows: 0,
        bytes: 0,
        objects: 0,
        source_min_id: nil,
        source_max_id: nil
      }
      object_results = []
      @archive.each_object_record do |object_record|
        result = inspect_object(object_record)
        totals[:rows] += result.fetch(:rows)
        totals[:bytes] += result.fetch(:bytes)
        totals[:objects] += 1
        totals[:source_min_id] = [ totals[:source_min_id], result.fetch(:source_min_id) ].compact.min
        totals[:source_max_id] = [ totals[:source_max_id], result.fetch(:source_max_id) ].compact.max
        object_results << result if object_results.size < TelemetryArchive::OBJECT_RESULT_LIMIT
      end
      verify_manifest_totals!(totals)
      verify_manifest_source_range!(totals)

      {
        archive_id: @archive.id,
        status: "verified",
        checksum_sha256: @archive.checksum_sha256,
        rows: totals.fetch(:rows),
        bytes: totals.fetch(:bytes),
        object_count: totals.fetch(:objects),
        objects: object_results,
        objects_truncated: totals.fetch(:objects) > object_results.size
      }
    rescue SystemStackError => error
      wrapped = VerificationError.new("Archive verification failed: #{error.class}: #{error.message}")
      fail_manifest!(wrapped) if @persist
      raise wrapped
    rescue VerificationError
      fail_manifest!($!) if @persist
      raise
    rescue StandardError => error
      wrapped = VerificationError.new("Archive verification failed: #{error.class}: #{error.message}")
      fail_manifest!(wrapped) if @persist
      raise wrapped
    end

    def verify_manifest_metadata!
      scope = @archive.object_record_scope
      totals = {
        rows: scope.sum(:expected_rows),
        bytes: scope.sum(:expected_bytes),
        objects: scope.count,
        source_min_id: scope.minimum(:source_min_id),
        source_max_id: scope.maximum(:source_max_id)
      }
      verify_manifest_totals!(totals)
      verify_manifest_source_range!(totals)
      verify_manifest_checksum!
      totals
    end

    def inspect_object!(object_record)
      inspect_object(object_record)
    end

    private

    def inspect_and_persist_objects(manifest_totals)
      object_results = []
      processed = 0
      @archive.each_object_record do |object_record|
        next if object_record.verified?
        break if @object_limit && processed >= @object_limit

        result = inspect_object(object_record)
        processed += 1
        object_results << result if object_results.size < TelemetryArchive::OBJECT_RESULT_LIMIT
      end

      remaining = @archive.object_record_scope.where.not(status: "verified").count
      verified_scope = @archive.object_record_scope.verified
      verified_rows = verified_scope.sum(:verified_rows)
      verified_bytes = verified_scope.sum(:verified_bytes)
      if remaining.zero?
        complete_manifest!(manifest_totals)
      else
        @archive.update!(
          status: "verifying",
          verified_rows: verified_rows,
          verified_bytes: verified_bytes,
          verification_started_at: @archive.verification_started_at || Time.current,
          failed_at: nil,
          error_message: nil
        )
      end

      {
        archive_id: @archive.id,
        status: remaining.zero? ? "verified" : "verifying",
        checksum_sha256: @archive.checksum_sha256,
        rows: remaining.zero? ? manifest_totals.fetch(:rows) : verified_rows,
        bytes: remaining.zero? ? manifest_totals.fetch(:bytes) : verified_bytes,
        expected_rows: manifest_totals.fetch(:rows),
        expected_bytes: manifest_totals.fetch(:bytes),
        object_count: manifest_totals.fetch(:objects),
        verified_object_count: manifest_totals.fetch(:objects) - remaining,
        objects_processed: processed,
        objects: object_results,
        objects_truncated: processed > object_results.size,
        continuation_required: remaining.positive?
      }
    end

    def inspect_object(object_record)
      @work_fence&.call
      object_record.update!(status: "verifying", error_message: nil) if @persist
      payload = @storage_service.download(object_record.object_key)
      actual_bytes = payload.bytesize
      actual_checksum = Digest::SHA256.hexdigest(payload)
      verify_value!(object_record.expected_bytes, actual_bytes, object_record, "bytes")
      verify_value!(object_record.checksum_sha256, actual_checksum, object_record, "SHA-256")
      rows = parse_rows(payload, object_record.object_key)
      references = rows.map { |row| normalized_row_reference(row) }

      verify_value!(object_record.expected_rows, rows.size, object_record, "rows")
      verify_value!(object_record.normalized_source_references, references, object_record, "source references")
      verify_row_contract!(rows, object_record)

      if @persist
        object_record.update!(
          status: "verified",
          verified_rows: rows.size,
          verified_bytes: actual_bytes,
          verified_at: Time.current,
          error_message: nil
        )
      end

      {
        object_id: object_record.id,
        key: object_record.object_key,
        checksum_sha256: actual_checksum,
        rows: rows.size,
        bytes: actual_bytes,
        source_min_id: object_record.source_min_id,
        source_max_id: object_record.source_max_id
      }
    rescue StandardError => error
      if @persist && object_record.persisted?
        object_record.update_columns(
          status: "failed",
          error_message: "#{error.class}: #{error.message}",
          updated_at: Time.current
        )
      end
      raise
    end

    def parse_rows(payload, key)
      body = Zlib::GzipReader.new(StringIO.new(payload)).read
      body.each_line.filter_map do |line|
        stripped = line.strip
        next if stripped.empty?

        JSON.parse(stripped)
      end
    rescue Zlib::Error, JSON::ParserError => error
      raise VerificationError, "Archive object #{key} is not valid gzip JSONL: #{error.message}"
    end

    def normalized_row_reference(row)
      identity = row["source_identity"] || {}
      {
        "id" => (identity["id"] || row.dig("attributes", "id")).to_i,
        "timestamp" => identity["timestamp"].presence
      }
    end

    def verify_row_contract!(rows, object_record)
      rows.each do |row|
        unless row["archive_version"].to_i == 2 && row["manifest_id"].to_i == @archive.id
          raise VerificationError, "Archive object #{object_record.object_key} contains a row from another manifest"
        end
        unless row["record_type"] == @archive.record_type
          raise VerificationError, "Archive object #{object_record.object_key} contains the wrong record type"
        end
        unless row["attributes"].is_a?(Hash)
          raise VerificationError, "Archive object #{object_record.object_key} contains a row without attributes"
        end
      end
    end

    def verify_value!(expected, actual, object_record, label)
      return if expected == actual

      raise VerificationError,
            "Archive object #{object_record.object_key} #{label} mismatch: expected #{expected.inspect}, got #{actual.inspect}"
    end

    def verify_manifest_totals!(totals)
      unless totals.fetch(:rows) == @archive.expected_rows && totals.fetch(:bytes) == @archive.expected_bytes
        raise VerificationError,
              "Archive manifest totals mismatch: expected #{@archive.expected_rows} rows/#{@archive.expected_bytes} bytes, " \
              "got #{totals.fetch(:rows)} rows/#{totals.fetch(:bytes)} bytes"
      end
    end

    def verify_manifest_checksum!
      actual = @archive.manifest_checksum_sha256
      return if ActiveSupport::SecurityUtils.secure_compare(actual, @archive.checksum_sha256.to_s)

      raise VerificationError,
            "Archive manifest checksum mismatch: expected #{@archive.checksum_sha256.inspect}, got #{actual.inspect}"
    end

    def verify_manifest_source_range!(totals)
      return if totals.fetch(:objects).zero?

      actual_min = totals.fetch(:source_min_id)
      actual_max = totals.fetch(:source_max_id)
      unless actual_min == @archive.source_min_id && actual_max == @archive.source_max_id
        raise VerificationError,
              "Archive manifest source range mismatch: expected #{@archive.source_min_id}-#{@archive.source_max_id}, " \
              "got #{actual_min}-#{actual_max}"
      end
    end

    def complete_manifest!(totals)
      now = Time.current
      metadata = @archive.lifecycle_metadata.is_a?(Hash) ? @archive.lifecycle_metadata.dup : {}
      @archive.reload.update!(
        status: "completed",
        verified_rows: totals.fetch(:rows),
        verified_bytes: totals.fetch(:bytes),
        verified_at: now,
        completed_at: now,
        failed_at: nil,
        error_message: nil,
        objects: [],
        lifecycle_metadata: metadata.merge(
          "object_catalog" => "telemetry_archive_objects",
          "object_count" => totals.fetch(:objects)
        )
      )
    end

    def inspect_legacy_archive
      objects = @archive.archive_objects
      raise VerificationError, "Legacy archive has no recorded objects" if objects.empty? && @archive.rows.to_i.positive?

      {
        archive_id: @archive.id,
        status: "legacy_unverifiable",
        rows: @archive.rows,
        bytes: @archive.bytes,
        objects: objects,
        warning: "Manifest version 1 did not record SHA-256 checksums or exact source identities"
      }
    end

    def fail_manifest!(error)
      @archive.update_columns(
        status: "failed",
        failed_at: Time.current,
        error_message: "#{error.class}: #{error.message}",
        updated_at: Time.current
      )
    end
  end
end
