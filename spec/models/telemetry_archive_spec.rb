# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryArchive, type: :model do
  describe "bounded v2 object iteration" do
    it "preserves the legacy manifest digest without loading the association" do
      archive = create(:telemetry_archive, :verified_manifest, rows: 3)
      objects = 3.times.map do |sequence|
        create(
          :telemetry_archive_object,
          telemetry_archive: archive,
          sequence: sequence,
          object_key: "telemetry/archive=#{archive.id}/part-#{sequence}.jsonl.gz",
          source_min_id: sequence + 1,
          source_max_id: sequence + 1,
          source_references: [
            { "id" => sequence + 1, "timestamp" => 1.day.ago.utc.iso8601(6) }
          ]
        )
      end
      legacy_payload = objects.map(&:checksum_attributes).to_json

      expect(archive.manifest_checksum_payload).to eq(legacy_payload)
      expect(archive.manifest_checksum_sha256).to eq(Digest::SHA256.hexdigest(legacy_payload))
      expect(archive.each_object_record.map(&:id)).to eq(objects.map(&:id))
      expect(archive.association(:object_records)).not_to be_loaded
    end

    it "limits result summaries while reporting object keys from canonical rows" do
      archive = create(:telemetry_archive, :verified_manifest)
      3.times do |sequence|
        create(
          :telemetry_archive_object,
          telemetry_archive: archive,
          sequence: sequence,
          object_key: "telemetry/archive=#{archive.id}/part-#{sequence}.jsonl.gz"
        )
      end

      expect(archive.object_summaries(limit: 2).size).to eq(2)
      expect(archive.object_keys).to eq(archive.object_record_scope.order(:sequence).pluck(:object_key))
    end
  end
end
