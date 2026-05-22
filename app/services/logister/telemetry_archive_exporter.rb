require "digest/md5"
require "json"
require "stringio"
require "zlib"

module Logister
  class TelemetryArchiveExporter
    class Error < StandardError; end

    RECORD_TYPES = {
      "ingest_events" => IngestEvent,
      "trace_spans" => TraceSpan
    }.freeze
    DEFAULT_BATCH_SIZE = 1_000

    def initialize(record_type:, before:, after: nil, batch_size: DEFAULT_BATCH_SIZE, prefix: ENV.fetch("LOGISTER_ARCHIVE_PREFIX", "telemetry"), storage_service: nil, dry_run: false)
      @record_type = record_type.to_s
      @before = before
      @after = after
      @batch_size = batch_size.to_i.positive? ? batch_size.to_i : DEFAULT_BATCH_SIZE
      @prefix = prefix.to_s.delete_prefix("/").delete_suffix("/")
      @storage_service = storage_service || archive_storage_service
      @dry_run = dry_run
    end

    def call
      exported_rows = 0
      objects = []

      relation.in_batches(of: @batch_size) do |batch_relation|
        records = batch_relation.order(:id).to_a
        next if records.empty?

        payload = gzip_records(records)
        key = object_key(records)
        checksum = Digest::MD5.base64digest(payload)
        exported_rows += records.size

        @storage_service.upload(
          key,
          StringIO.new(payload),
          checksum: checksum,
          content_type: "application/jsonl+gzip"
        ) unless @dry_run

        objects << {
          key: key,
          rows: records.size,
          bytes: payload.bytesize,
          dry_run: @dry_run
        }
      end

      {
        record_type: @record_type,
        before: @before.utc.iso8601,
        after: @after&.utc&.iso8601,
        batch_size: @batch_size,
        objects: objects,
        rows: exported_rows,
        dry_run: @dry_run
      }
    end

    private

    def relation
      scope = model.where("created_at < ?", @before)
      scope = scope.where("created_at >= ?", @after) if @after
      scope.order(:id)
    end

    def model
      RECORD_TYPES.fetch(@record_type) do
        raise Error, "Unsupported telemetry archive record type: #{@record_type.inspect}"
      end
    end

    def archive_storage_service
      service_name = ENV["LOGISTER_ARCHIVE_STORAGE_SERVICE"].to_s.presence
      return ActiveStorage::Blob.service if service_name.blank?

      ActiveStorage::Blob.services.fetch(service_name.to_sym)
    rescue KeyError
      raise Error, "Unknown telemetry archive storage service: #{service_name.inspect}"
    end

    def gzip_records(records)
      io = StringIO.new
      Zlib::GzipWriter.wrap(io) do |gzip|
        records.each do |record|
          gzip.write(JSON.generate(archive_row(record)))
          gzip.write("\n")
        end
      end
      io.string
    end

    def archive_row(record)
      {
        archive_version: 1,
        record_type: @record_type,
        exported_at: Time.current.utc.iso8601,
        attributes: record.attributes.as_json
      }
    end

    def object_key(records)
      timestamp = records.first.created_at.utc
      exported_at = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
      range = "#{records.first.id}-#{records.last.id}"

      [
        @prefix,
        @record_type,
        "year=#{timestamp.year}",
        "month=#{timestamp.strftime('%m')}",
        "day=#{timestamp.strftime('%d')}",
        "#{exported_at}-#{range}.jsonl.gz"
      ].join("/")
    end
  end
end
