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
    project = create(:project)
    event = create(:ingest_event, project: project, occurred_at: 2.days.ago)

    result = described_class.new(
      record_type: "ingest_events",
      project: project,
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
    project = create(:project)
    create(:ingest_event, project: project, occurred_at: 2.days.ago)

    result = described_class.new(
      record_type: "ingest_events",
      project: project,
      before: 1.day.ago,
      storage_service: storage,
      dry_run: true
    ).call

    expect(result[:rows]).to eq(1)
    expect(storage.uploads).to be_empty
  end

  it "honors an after boundary" do
    storage = FakeArchiveStorage.new
    old_event = create(:ingest_event, occurred_at: 4.days.ago, created_at: 4.days.ago, updated_at: 4.days.ago)
    kept_event = create(:ingest_event, occurred_at: 2.days.ago, created_at: 2.days.ago, updated_at: 2.days.ago)

    result = described_class.new(
      record_type: "ingest_events",
      before: 1.day.ago,
      after: 3.days.ago,
      storage_service: storage
    ).call

    body = Zlib::GzipReader.new(StringIO.new(storage.uploads.first[:payload])).read
    ids = body.lines.map { |line| JSON.parse(line).dig("attributes", "id") }

    expect(result[:rows]).to eq(1)
    expect(ids).to contain_exactly(kept_event.id)
    expect(ids).not_to include(old_event.id)
  end

  it "archives trace spans" do
    storage = FakeArchiveStorage.new
    span = create(:trace_span, started_at: 2.days.ago, created_at: 2.days.ago, updated_at: 2.days.ago)

    result = described_class.new(
      record_type: "trace_spans",
      before: 1.day.ago,
      storage_service: storage
    ).call

    body = Zlib::GzipReader.new(StringIO.new(storage.uploads.first[:payload])).read
    row = JSON.parse(body.lines.first)

    expect(result[:rows]).to eq(1)
    expect(row["record_type"]).to eq("trace_spans")
    expect(row.dig("attributes", "id")).to eq(span.id)
  end

  it "filters archive rows by project and ingest event type" do
    storage = FakeArchiveStorage.new
    project = create(:project)
    matching_event = create(:ingest_event, :log, project: project, occurred_at: 2.days.ago)
    create(:ingest_event, project: project, occurred_at: 2.days.ago)
    create(:ingest_event, :log, occurred_at: 2.days.ago)

    result = described_class.new(
      record_type: "ingest_events",
      project: project,
      event_types: [ "log" ],
      before: 1.day.ago,
      storage_service: storage
    ).call

    body = Zlib::GzipReader.new(StringIO.new(storage.uploads.first[:payload])).read
    ids = body.lines.map { |line| JSON.parse(line).dig("attributes", "id") }

    expect(result[:rows]).to eq(1)
    expect(result[:project_id]).to eq(project.id)
    expect(storage.uploads.first[:key]).to include("project=#{project.uuid}")
    expect(ids).to contain_exactly(matching_event.id)
  end

  it "omits an empty key prefix without producing a leading slash" do
    storage = FakeArchiveStorage.new
    create(:ingest_event, occurred_at: 2.days.ago, created_at: 2.days.ago, updated_at: 2.days.ago)

    described_class.new(
      record_type: "ingest_events",
      before: 1.day.ago,
      prefix: "",
      storage_service: storage
    ).call

    expect(storage.uploads.first[:key]).to start_with("ingest_events/")
    expect(storage.uploads.first[:key]).not_to start_with("/")
  end

  it "returns an empty archive result when no rows match" do
    storage = FakeArchiveStorage.new

    result = described_class.new(
      record_type: "ingest_events",
      before: 100.years.ago,
      storage_service: storage
    ).call

    expect(result[:rows]).to eq(0)
    expect(result[:objects]).to eq([])
    expect(storage.uploads).to be_empty
  end

  it "falls back to the default batch size for invalid values" do
    storage = FakeArchiveStorage.new

    result = described_class.new(
      record_type: "ingest_events",
      before: 100.years.ago,
      batch_size: 0,
      storage_service: storage
    ).call

    expect(result[:batch_size]).to eq(described_class::DEFAULT_BATCH_SIZE)
  end

  it "raises a clear error for unsupported record types" do
    storage = FakeArchiveStorage.new

    expect {
      described_class.new(record_type: "unknown", before: Time.current, storage_service: storage).call
    }.to raise_error(Logister::TelemetryArchiveExporter::Error, /Unsupported telemetry archive record type/)
  end
end
