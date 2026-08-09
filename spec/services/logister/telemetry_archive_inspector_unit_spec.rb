# frozen_string_literal: true

require "spec_helper"
require_relative "../../../config/environment"
require "digest"
require "json"
require "stringio"
require "zlib"

RSpec.describe Logister::TelemetryArchiveInspector do
  class UnitArchiveObject
    attr_reader :id, :object_key, :expected_bytes, :checksum_sha256, :expected_rows,
                :source_min_id, :source_max_id, :sequence

    def initialize(payload:, references:)
      @id = 9
      @sequence = 0
      @object_key = "telemetry/manifests/archive=42/part-000000.jsonl.gz"
      @expected_bytes = payload.bytesize
      @checksum_sha256 = Digest::SHA256.hexdigest(payload)
      @expected_rows = references.size
      @source_min_id = references.first.fetch("id")
      @source_max_id = references.last.fetch("id")
      @references = references
    end

    def normalized_source_references = @references

    def checksum_attributes
      {
        "sequence" => sequence,
        "object_key" => object_key,
        "checksum_sha256" => checksum_sha256,
        "expected_rows" => expected_rows,
        "expected_bytes" => expected_bytes,
        "source_references" => normalized_source_references
      }
    end
  end

  class UnitArchiveObjectCollection < Array
    def ordered = self
  end

  class UnitArchiveStorage
    def initialize(key, payload)
      @key = key
      @payload = payload
    end

    def download(key)
      raise KeyError, key unless key == @key

      @payload
    end
  end

  class UnitArchive
    attr_reader :id, :manifest_version, :record_type, :object_records,
                :expected_rows, :expected_bytes, :checksum_sha256,
                :source_min_id, :source_max_id

    def initialize(object_record)
      @id = 42
      @manifest_version = 2
      @record_type = "ingest_events"
      @object_records = UnitArchiveObjectCollection.new([ object_record ])
      @expected_rows = object_record.expected_rows
      @expected_bytes = object_record.expected_bytes
      @source_min_id = object_record.source_min_id
      @source_max_id = object_record.source_max_id
      @checksum_sha256 = Digest::SHA256.hexdigest(manifest_checksum_payload)
    end

    def manifest_checksum_payload
      object_records.map(&:checksum_attributes).to_json
    end
  end

  def gzip_row(row)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) do |gzip|
      gzip.mtime = 0
      gzip.write(JSON.generate(row))
      gzip.write("\n")
    end
    io.string
  end

  it "verifies exact bytes, rows, SHA-256, manifest ownership, and source identities" do
    reference = { "id" => 123, "timestamp" => "2026-08-01T12:00:00.000000Z" }
    payload = gzip_row(
      "archive_version" => 2,
      "manifest_id" => 42,
      "record_type" => "ingest_events",
      "source_identity" => reference,
      "attributes" => { "id" => 123, "message" => "archived" }
    )
    object_record = UnitArchiveObject.new(payload: payload, references: [ reference ])
    archive = UnitArchive.new(object_record)

    result = described_class.new(
      archive: archive,
      storage_service: UnitArchiveStorage.new(object_record.object_key, payload)
    ).call

    expect(result).to include(status: "verified", rows: 1, bytes: payload.bytesize)
  end

  it "rejects content that does not match the recorded checksum" do
    reference = { "id" => 123, "timestamp" => "2026-08-01T12:00:00.000000Z" }
    payload = gzip_row(
      "archive_version" => 2,
      "manifest_id" => 42,
      "record_type" => "ingest_events",
      "source_identity" => reference,
      "attributes" => { "id" => 123 }
    )
    object_record = UnitArchiveObject.new(payload: payload, references: [ reference ])
    archive = UnitArchive.new(object_record)

    expect {
      described_class.new(
        archive: archive,
        storage_service: UnitArchiveStorage.new(object_record.object_key, "tampered")
      ).call
    }.to raise_error(Logister::TelemetryArchiveInspector::VerificationError, /not valid|mismatch/)
  end
end
