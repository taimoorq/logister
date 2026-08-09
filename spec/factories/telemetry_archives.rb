# frozen_string_literal: true

require "digest/md5"

FactoryBot.define do
  factory :telemetry_archive do
    association :project
    record_type { "ingest_events" }
    scope { "hot_events" }
    status { "completed" }
    before_at { 30.days.ago }
    after_at { nil }
    rows { 1 }
    bytes { 128 }
    objects { [ { "key" => "telemetry/ingest_events/example.jsonl.gz", "rows" => 1, "bytes" => 128 } ] }
    dry_run { false }

    trait :verified_manifest do
      manifest_version { 2 }
      expected_rows { rows }
      expected_bytes { bytes }
      verified_rows { rows }
      verified_bytes { bytes }
      verified_at { Time.current }
      completed_at { Time.current }
      exported_at { 1.minute.ago }
      checksum_sha256 { Digest::SHA256.hexdigest("manifest") }
    end
  end

  factory :telemetry_archive_object do
    association :telemetry_archive, factory: [ :telemetry_archive, :verified_manifest ]
    sequence(:sequence) { |number| number }
    status { "verified" }
    sequence(:object_key) { |number| "telemetry/manifests/archive=#{telemetry_archive.id}/part-#{number}.jsonl.gz" }
    content_type { "application/jsonl+gzip" }
    checksum_sha256 { Digest::SHA256.hexdigest("payload") }
    checksum_md5_base64 { Digest::MD5.base64digest("payload") }
    expected_rows { 1 }
    expected_bytes { 7 }
    verified_rows { expected_rows }
    verified_bytes { expected_bytes }
    source_min_id { 1 }
    source_max_id { 1 }
    source_references { [ { "id" => 1, "timestamp" => 1.day.ago.utc.iso8601(6) } ] }
    uploaded_at { 1.minute.ago }
    verified_at { Time.current }
  end
end
