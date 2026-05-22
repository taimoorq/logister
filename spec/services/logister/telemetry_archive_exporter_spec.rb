# frozen_string_literal: true

require "rails_helper"
require "zlib"

RSpec.describe Logister::TelemetryArchiveExporter, type: :model do
  class FakeArchiveStorage
    attr_reader :uploads

    def initialize
      @uploads = []
    end

    def upload(key, io, checksum:, content_type:)
      @uploads << {
        key: key,
        payload: io.read,
        checksum: checksum,
        content_type: content_type
      }
    end
  end

  it "uploads compressed JSONL batches for telemetry records" do
    storage = FakeArchiveStorage.new
    event = ingest_events(:one)
    event.update!(created_at: 2.days.ago)

    result = described_class.new(
      record_type: "ingest_events",
      before: 1.day.ago,
      batch_size: 100,
      prefix: "telemetry-test",
      storage_service: storage
    ).call

    expect(result[:rows]).to eq(1)
    expect(storage.uploads.size).to eq(1)
    upload = storage.uploads.first
    expect(upload[:key]).to include("telemetry-test/ingest_events/")
    expect(upload[:content_type]).to eq("application/jsonl+gzip")

    body = Zlib::GzipReader.new(StringIO.new(upload[:payload])).read
    row = JSON.parse(body.lines.first)
    expect(row["record_type"]).to eq("ingest_events")
    expect(row.dig("attributes", "id")).to eq(event.id)
  end

  it "supports dry runs without uploading" do
    storage = FakeArchiveStorage.new
    ingest_events(:one).update!(created_at: 2.days.ago)

    result = described_class.new(
      record_type: "ingest_events",
      before: 1.day.ago,
      storage_service: storage,
      dry_run: true
    ).call

    expect(result[:rows]).to eq(1)
    expect(storage.uploads).to be_empty
  end
end
