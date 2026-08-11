# frozen_string_literal: true

require "json"
require "securerandom"

abort "archive_retention_capacity must run with RAILS_ENV=test" unless Rails.env.test?

object_count = Integer(ENV.fetch("ARCHIVE_CAPACITY_OBJECTS", 1_371))
references_per_object = Integer(ENV.fetch("ARCHIVE_CAPACITY_REFERENCES_PER_OBJECT", 1_000))
abort "capacity dimensions must be positive" unless object_count.positive? && references_per_object.positive?

def rss_kilobytes
  IO.popen([ "ps", "-o", "rss=", "-p", Process.pid.to_s ], &:read).to_i
rescue StandardError
  0
end

result = nil
ActiveRecord::Base.transaction(requires_new: true) do
  project = Project.first || raise("The test database needs one project fixture")
  prefix = "capacity-#{SecureRandom.uuid}"
  archive = project.telemetry_archives.create!(
    record_type: "ingest_events",
    scope: "hot_events",
    status: "verifying",
    before_at: Time.zone.parse("2026-01-01 00:00:00"),
    rows: object_count * references_per_object,
    bytes: object_count,
    objects: [],
    manifest_version: 2,
    expected_rows: object_count * references_per_object,
    expected_bytes: object_count
  )

  connection = ActiveRecord::Base.connection
  connection.execute(<<~SQL.squish)
    WITH object_sequences AS (
      SELECT generate_series(0, #{connection.quote(object_count - 1)})::integer AS sequence
    ), object_references AS (
      SELECT
        object_sequences.sequence,
        jsonb_agg(
          jsonb_build_object(
            'id', (object_sequences.sequence::bigint * #{connection.quote(references_per_object)}) + reference_number,
            'timestamp', '2026-01-01T00:00:00.000000Z'
          )
          ORDER BY reference_number
        ) AS source_references
      FROM object_sequences
      CROSS JOIN LATERAL generate_series(1, #{connection.quote(references_per_object)}) AS reference_number
      GROUP BY object_sequences.sequence
    )
    INSERT INTO telemetry_archive_objects (
      telemetry_archive_id,
      sequence,
      status,
      object_key,
      content_type,
      checksum_sha256,
      checksum_md5_base64,
      expected_rows,
      expected_bytes,
      verified_rows,
      verified_bytes,
      source_min_id,
      source_max_id,
      source_references,
      uploaded_at,
      verified_at,
      created_at,
      updated_at
    )
    SELECT
      #{connection.quote(archive.id)},
      object_references.sequence,
      'verified',
      #{connection.quote(prefix)} || '/part-' || object_references.sequence || '.jsonl.gz',
      'application/jsonl+gzip',
      md5(#{connection.quote(prefix)} || object_references.sequence::text) || md5(object_references.sequence::text || #{connection.quote(prefix)}),
      md5(#{connection.quote(prefix)} || object_references.sequence::text),
      #{connection.quote(references_per_object)},
      1,
      #{connection.quote(references_per_object)},
      1,
      (object_references.sequence::bigint * #{connection.quote(references_per_object)}) + 1,
      (object_references.sequence::bigint + 1) * #{connection.quote(references_per_object)},
      object_references.source_references,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    FROM object_references
  SQL

  GC.start(full_mark: true, immediate_sweep: true)
  baseline_live_slots = GC.stat.fetch(:heap_live_slots)
  baseline_rss_kb = rss_kilobytes
  peak_rss_kb = baseline_rss_kb
  sampling = true
  sampler = Thread.new do
    while sampling
      peak_rss_kb = [ peak_rss_kb, rss_kilobytes ].max
      sleep(0.1)
    end
  end

  query_count = 0
  subscriber = nil
  begin
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      query_count += 1 unless payload[:name].in?(%w[SCHEMA CACHE])
    end
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    checksum = archive.manifest_checksum_sha256
    reference_count = 0
    maximum_reference_batch = 0
    archive.each_source_reference_batch do |references, _object|
      reference_count += references.size
      maximum_reference_batch = [ maximum_reference_batch, references.size ].max
    end
    object_page = ProjectArchiveObjectCatalog.new(archives: [ archive ]).call.fetch(archive.id)
    duration_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    sampling = false
    sampler.join
  end
  GC.start(full_mark: true, immediate_sweep: true)
  final_live_slots = GC.stat.fetch(:heap_live_slots)
  final_rss_kb = rss_kilobytes

  expected_references = object_count * references_per_object
  raise "streamed reference count mismatch" unless reference_count == expected_references
  raise "reference batch exceeded one archive object" unless maximum_reference_batch == references_per_object
  raise "catalog page is not bounded" unless object_page.total == object_count && object_page.object_keys.size == 20
  raise "archive association was materialized" if archive.association(:object_records).loaded?
  raise "streaming checksum is invalid" unless checksum.match?(/\A[0-9a-f]{64}\z/)

  result = {
    objects: object_count,
    references: reference_count,
    maximum_reference_batch: maximum_reference_batch,
    catalog_page_size: object_page.object_keys.size,
    association_loaded: archive.association(:object_records).loaded?,
    sql_queries: query_count,
    duration_seconds: duration_seconds.round(3),
    baseline_rss_mb: (baseline_rss_kb / 1024.0).round(2),
    peak_rss_mb: (peak_rss_kb / 1024.0).round(2),
    final_rss_mb: (final_rss_kb / 1024.0).round(2),
    peak_rss_delta_mb: ((peak_rss_kb - baseline_rss_kb) / 1024.0).round(2),
    retained_heap_slots: final_live_slots - baseline_live_slots,
    checksum_sha256: checksum
  }

  raise ActiveRecord::Rollback
end

puts JSON.pretty_generate(result)
