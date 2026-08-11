# frozen_string_literal: true

require "json"
require "digest"
require "stringio"
require "zlib"

module Logister
  class TelemetryArchiveReplay
    class ReplayError < StandardError; end

    def initialize(archive:, storage_service: nil, processor: nil, verify: true)
      @archive = archive
      locator = archive.lifecycle_metadata&.dig("storage_locator")
      @storage_service = storage_service || InstanceConfiguration::ArchiveService.build(locator: locator)
      @processor = processor
      @verify = verify
    end

    def call
      verify_archive! if @verify
      processed = 0

      each_row do |row, object_record|
        @processor&.call(
          row,
          idempotency_key: replay_idempotency_key(row, object_record),
          archive: @archive
        )
        processed += 1
      end

      object_count = @archive.object_record_scope.count
      object_keys = @archive.object_record_scope
        .order(:sequence, :id)
        .limit(TelemetryArchive::OBJECT_RESULT_LIMIT)
        .pluck(:object_key)

      {
        archive_id: @archive.id,
        rows: processed,
        object_count: object_count,
        object_keys: object_keys,
        object_keys_truncated: object_count > object_keys.size,
        processor: @processor.present?
      }
    end

    def each_row
      return enum_for(:each_row) unless block_given?

      @archive.each_object_record do |object_record|
        payload = @storage_service.download(object_record.object_key)
        unless payload.bytesize == object_record.expected_bytes &&
            Digest::SHA256.hexdigest(payload) == object_record.checksum_sha256
          raise ReplayError, "Archive object changed after manifest verification: #{object_record.object_key}"
        end
        body = Zlib::GzipReader.new(StringIO.new(payload)).read
        body.each_line do |line|
          next if line.blank?

          yield JSON.parse(line), object_record
        end
      end
    rescue Zlib::Error, JSON::ParserError => error
      raise ReplayError, "Archive replay could not read object: #{error.class}: #{error.message}"
    end

    private

    def verify_archive!
      unless @archive.verified?
        raise ReplayError, "Archive must have a verified manifest before replay"
      end

      TelemetryArchiveInspector.new(
        archive: @archive,
        storage_service: @storage_service,
        persist: false
      ).call
    end

    def replay_idempotency_key(row, object_record)
      source_id = row.dig("source_identity", "id") || row.dig("attributes", "id")
      "telemetry-archive/#{@archive.id}/#{object_record.sequence}/#{source_id}"
    end
  end
end
