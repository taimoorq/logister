# frozen_string_literal: true

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
  end
end
