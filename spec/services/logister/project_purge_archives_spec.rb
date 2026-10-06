# frozen_string_literal: true

require "rails_helper"
require "stringio"
require "tmpdir"

RSpec.describe Logister::ProjectPurgeAdapters::Archives, type: :model do
  let(:now) { Time.current.change(usec: 0) }
  let(:project) { create(:project) }
  let(:purge) { create(:project_purge, project: project, tombstoned_at: now - 3.minutes) }
  let(:service) { InstanceConfiguration::ArchiveService.build(locator: @locator) }
  let(:key) { "archives/#{project.uuid}/events.json.gz" }

  around do |example|
    previous = ENV.delete("LOGISTER_ATTEST_LEGACY_ARCHIVE_STORAGE_CURRENT")
    Dir.mktmpdir("logister-purge-archives") do |directory|
      @locator = InstanceConfiguration::ArchiveService.with_generation_id("service" => "local", "root" => directory)
      example.run
    end
  ensure
    previous.nil? ? ENV.delete("LOGISTER_ATTEST_LEGACY_ARCHIVE_STORAGE_CURRENT") : ENV["LOGISTER_ATTEST_LEGACY_ARCHIVE_STORAGE_CURRENT"] = previous
  end

  def archive_for(owner: project, object_key: key, locator: @locator)
    archive = owner.telemetry_archives.create!(
      record_type: "ingest_events", scope: "all", before_at: now, status: "completed",
      rows: 0, bytes: 9, manifest_version: 2
    )
    archive.object_records.create!(
      sequence: 0, object_key: object_key, content_type: "application/gzip", status: "verified",
      checksum_sha256: Digest::SHA256.hexdigest("telemetry"),
      checksum_md5_base64: Digest::MD5.base64digest("telemetry"),
      expected_rows: 0, expected_bytes: 9, source_min_id: 0, source_max_id: 0,
      storage_locator: locator || {}, storage_generation: locator&.fetch("generation_id", nil)
    )
    service.upload(object_key, StringIO.new("telemetry"))
    archive
  end

  it "waits for pre-tombstone uploads to quiesce before deleting objects" do
    archive = archive_for
    purge.update!(tombstoned_at: now)

    result = described_class.new(project_purge: purge, now: now).call

    expect(result).to include(status: "awaiting_external", phase: "write_quiescence", verified_absent: false)
    expect(service.exist?(key)).to be(true)
    expect(archive.reload.status).to eq("completed")
  end

  it "deletes recorded objects, verifies again on retry, and preserves another project's objects" do
    archive = archive_for
    other_key = "archives/another-project/events.json.gz"
    other_archive = archive_for(owner: create(:project), object_key: other_key)

    first = described_class.new(project_purge: purge, now: now).call

    expect(first).to include(status: "awaiting_external", phase: "mutation_complete", verified_absent: false)
    expect(first.fetch(:deletion_summary)).to include(deleted_objects: 1)
    expect(service.exist?(key)).to be(false)
    expect(archive.reload.status).to eq("completed")
    purge.steps.find_by!(store_name: "archives").update!(result: first)

    second = described_class.new(project_purge: purge, now: now + 31.seconds).call

    expect(second).to include(status: "completed", already_absent_objects: 1, verified_absent: true)
    expect(archive.reload.status).to eq("deleted")
    expect(archive.object_records.sole).to have_attributes(status: "deleted", deleted_at: be_present)
    expect(service.exist?(other_key)).to be(true)
    expect(other_archive.reload.status).to eq("completed")
  end

  it "preserves legacy objects without an immutable storage locator" do
    archive_for(locator: nil)

    result = described_class.new(project_purge: purge, now: now).call

    expect(result).to include(status: "awaiting_external", verified_absent: false)
    expect(result.fetch(:reason)).to include("no immutable storage locator")
    expect(service.exist?(key)).to be(true)
  end

  it "uses the attested current store for legacy objects" do
    archive_for(locator: nil)
    ENV["LOGISTER_ATTEST_LEGACY_ARCHIVE_STORAGE_CURRENT"] = "true"
    allow(InstanceConfiguration::ArchiveService).to receive(:current_locator).and_return(@locator)

    result = described_class.new(project_purge: purge, now: now).call

    expect(result).to include(status: "awaiting_external", phase: "mutation_complete")
    expect(service.exist?(key)).to be(false)
  end

  it "preserves objects when their recorded storage generation cannot be resolved" do
    archive_for(locator: { "generation_id" => "unknown" })

    result = described_class.new(project_purge: purge, now: now).call

    expect(result).to include(status: "awaiting_external", verified_absent: false)
    expect(result.fetch(:reason)).to include("cannot be resolved")
    expect(service.exist?(key)).to be(true)
  end

  it "requires project control-plane records before treating archive cleanup as complete" do
    missing_project_purge = instance_double(ProjectPurge, source_project_id: -1)

    result = described_class.new(project_purge: missing_project_purge, now: now).call

    expect(result).to include(status: "awaiting_external", verified_absent: false)
    expect(result.fetch(:reason)).to include("control-plane rows disappeared")
  end
end
