# Telemetry Storage and Retention

Logister uses PostgreSQL for app data and hot event detail, Redis for cache and Sidekiq, ClickHouse for analytics rollups, and optional S3 storage for cold telemetry archives.

For Redis durability, queue isolation, and database pool sizing, see [Redis, workers, and database pools](redis-worker-operations.md).

## ClickHouse Readiness

`/health/clickhouse` checks the schema-v2 append tables, deduplicated logical fact views, typed minute/hour views, and required column types—not only that ClickHouse answers `SELECT 1`.

Use the idempotent schema repair task after provisioning ClickHouse or upgrading an existing Logister installation:

```sh
bin/rails logister:clickhouse:schema:repair
bin/rails logister:clickhouse:schema:status
```

The repair task creates missing objects, adds compatible typed columns, updates event-type enum drift, and fails if the final schema is not ready. It intentionally does not recreate the v1 materialized rollups: a materialized view fed directly from an at-least-once append table can permanently inflate averages and percentiles after an ambiguous replay. `bin/release` always invokes repair and receives a no-op result when ClickHouse is disabled. Set `LOGISTER_CLICKHOUSE_MIGRATION_USERNAME` and `LOGISTER_CLICKHOUSE_MIGRATION_PASSWORD` when schema DDL should use a separate operator account from normal inserts and analytics queries.

The canonical schema lives in `docs/clickhouse_schema.sql`. `events_raw` and `spans_raw` are append/replay tables; product queries use `event_facts_v2` and `span_facts_v2`, which select one projector version per project and telemetry UUID. Typed metric, transaction, error, log, check-in, and request-span minute/hour views are derived from those logical facts. The existing `logister:clickhouse:schema:load` task remains an alias for the same create-and-repair behavior.

Use `LOGISTER_CLICKHOUSE_MODE=dual_write` or **Admin → Installation → ClickHouse** only while the analytics copy is being populated and verified. Dual write continues serving supported dashboard analytics from PostgreSQL, so it does not improve slow overview graphs by itself. Retained PostgreSQL events and spans can be copied with idempotent, bounded backfills:

```sh
SOURCE_COMPLETE_FROM=2026-06-01 CONFIRM=backfill \
  bin/rails 'logister:clickhouse:events:backfill[2026-06-01,2026-06-08]'
SOURCE_COMPLETE_FROM=2026-06-01 CONFIRM=backfill \
  bin/rails 'logister:clickhouse:spans:backfill[2026-06-01,2026-06-08]'
```

Both bounds are required. `SOURCE_COMPLETE_FROM` is an operator assertion backed by a retained-source inventory, verified archive manifest, or restored snapshot proving PostgreSQL is complete from that instant. Without it, the task may populate ClickHouse but will not certify watermarks: matching two partially retained stores is not historical completeness. Use `PROJECT_UUID=<uuid>` to limit a run to one tenant. Reconciliation is capped at 50,000 project/signal/hour buckets by default; split the range or projects, and use `ALLOW_LARGE_BACKFILL=1` only for a deliberately capacity-reviewed bulk run. The task output reports `verified`, `mismatch`, and `incomplete_deliveries` bucket counts. Do not switch reads until every requested bucket is verified and no projector delivery remains active.

The admin diagnostic compares logical UUID counts and an explicit canonical `UInt128` identity checksum over completed hourly buckets. Runtime routing requires an exact watermark for every requested project × signal × overlapping hour—including verified-zero sparse hours—and enforces the correct signal/destination pair. A successful query, one observed hour, or a table-wide count does not authorize a larger range. `ClickhouseCoverageSealerJob` runs hourly and rechecks the two most recently closed hours for projects with source, outbox, or nonzero watermark activity in that lookback. It seals empty signals for active tenants, skips wholly dormant tenants, processes projects in restartable pages, and relies on the recurring root run to repair a lost continuation. Open hours and inactive ranges without evidence fail closed to PostgreSQL. Watermarks older than the 90-day ClickHouse/read horizon are pruned by telemetry-ledger cleanup unless an incomplete delivery still needs the bucket. Raw ClickHouse facts retain 120 days, leaving a 30-day safety margin so TTL merges cannot delete a row while a 90-day watermark can still authorize it; schema repair applies the TTL change to existing raw tables.

Dashboard, Explorer, Insights, and performance responses expose the selected source, coverage ratio, freshness boundary, gaps, and sampled dual-read result. After the stable-window check passes, switch to `read_preferred` and restart web and worker processes; incomplete capabilities continue using PostgreSQL. The legacy `LOGISTER_CLICKHOUSE_ENABLED=true` setting selects only `dual_write`, so remove it when using `LOGISTER_CLICKHOUSE_MODE` or UI-managed settings.

No retained source rows and no watermarks is not proof of an empty historical range:
PostgreSQL retention may already have removed its replay copy. Such ranges fail closed
to PostgreSQL until an explicit delivery watermark exists.

Set `LOGISTER_CLICKHOUSE_DUAL_READ_SAMPLE_RATE` to a value from `0` to `1` during cutover. The default `0.01` deterministically compares one percent of complete ClickHouse reads with the equivalent PostgreSQL result and emits `clickhouse.dual_read.logister`. Use `0` after the evidence window or when PostgreSQL no longer retains the shadow range.

Transient ClickHouse failures open a cache-backed circuit after the configured threshold. While open, Logister skips requests for a short interval; one half-open probe then closes the circuit on success or reopens it on failure. The ClickHouse installation diagnostic exposes the current state, failure count, recovery time, and last canonical failure signature. Failure signatures remove row bodies, identifiers, row numbers, and timestamps so one outage is throttled as one failure shape.

## PostgreSQL partition maintenance

`IngestEventsPartitionMaintenanceJob` runs daily on the `maintenance` queue and idempotently creates the configured future monthly `ingest_events` partitions. PostgreSQL sends uncovered timestamps to the default partition instead of failing ingestion. The Redis & jobs diagnostic reports default-partition row counts grouped by month, earliest/latest timestamps, and whether the partition is drain-ready. If a target month contains default rows, automatic creation is intentionally blocked until an operator moves those rows; this avoids an unsafe implicit table rewrite during routine maintenance.

## PostgreSQL analytical transition runbook

ClickHouse ownership does not authorize an application migration to drop PostgreSQL indexes or source rows. Treat each reduction as a separately approved production operation with an observation window, a recorded recreation command, and a rollback threshold.

### Capture query and index evidence

Enable `pg_stat_statements` through the database provider or PostgreSQL configuration, then reset its statistics at the beginning of a representative observation window only if the operator has recorded the prior snapshot. Observe at least 30 days and include a month boundary, retention sweep, archive run, incident investigation, and normal weekday/weekend traffic.

```sql
SELECT
  queryid,
  calls,
  round(total_exec_time::numeric, 2) AS total_exec_ms,
  round(mean_exec_time::numeric, 2) AS mean_exec_ms,
  rows,
  left(query, 500) AS query_sample
FROM pg_stat_statements
WHERE query ILIKE '%ingest_events%'
   OR query ILIKE '%trace_spans%'
ORDER BY total_exec_time DESC
LIMIT 100;

SELECT
  s.schemaname,
  s.relname,
  s.indexrelname,
  s.idx_scan,
  s.last_idx_scan,
  pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
  pg_get_indexdef(s.indexrelid) AS recreate_sql
FROM pg_stat_user_indexes AS s
WHERE s.relname LIKE 'ingest_events%'
   OR s.relname = 'trace_spans'
ORDER BY pg_relation_size(s.indexrelid) DESC;
```

An `idx_scan` of zero is only a candidate signal. Exclude primary/unique indexes, indexes supporting foreign keys or exclusion constraints, and indexes used by rare operator, retention, archive, purge, or incident workflows. Correlate index evidence with normalized `pg_stat_statements` queries and `EXPLAIN (ANALYZE, BUFFERS)` on a restored production-sized copy.

For each approved candidate, save the exact `pg_get_indexdef` output, current size, statistics-reset timestamp, dependent constraints, and rollback threshold. Drop only one index at a time, outside a transaction, during a quiet window:

```sql
SET lock_timeout = '5s';
SET statement_timeout = '30min';
DROP INDEX CONCURRENTLY IF EXISTS public.example_candidate_index;
```

Monitor PostgreSQL latency, buffer reads, CPU, lock waits, ClickHouse fallback rate, retention duration, and archive duration for at least one full workload cycle. Roll back with the recorded definition changed to `CREATE INDEX CONCURRENTLY ...`; do not wait for several removals before evaluating impact. `DROP INDEX CONCURRENTLY` cannot run inside a Rails migration transaction and must remain an operator runbook action.

### Signal-specific replay buffers

These are initial hosted-service targets after 30 consecutive days of complete watermarks and successful sampled reconciliation. A project may choose a longer policy. A retention worker must never remove a source record while any projector delivery for that identity is pending, processing, retrying, or terminal-failed.

| PostgreSQL signal | Initial hot replay target | Required evidence before shortening |
| --- | --- | --- |
| Error occurrence event | 30 days | Error grouping complete; detail/archive lookup verified; ClickHouse `error` hours complete |
| Log event | 7 days | Explorer/Insights equivalence and archive policy verified; ClickHouse `log` hours complete |
| Metric event | 7 days | Custom metric count/value and percentile equivalence; ClickHouse `metric` hours complete |
| Transaction event | 14 days | Insights and transaction fallback equivalence; ClickHouse `transaction` hours complete |
| Check-in observation | 30 days | Monitor derivation complete and missed/error history verified; ClickHouse `check_in` hours complete |
| Trace span | 72 hours | Performance root/child mapping equivalence; ClickHouse `span` hours complete |

Keep idempotency/outbox identities and their immutable acceptance metadata for their separate 120-day retry horizon even when the hot source buffer is shorter, and retain projection watermarks for at least the longest user-query and reconciliation window. Retention locks each idempotency key, outbox, delivery set, and source in order; source deletion commits with `source_retired_at`, so a later retry can return its accepted identifiers while delivery repair refuses to create work that requires a deleted source. If an incomplete delivery approaches the source-retention boundary, alert and pause deletion rather than converting it into a missing-source terminal failure.

### `trace_spans` decision

The target architecture keeps `trace_spans` unpartitioned only as a 72-hour PostgreSQL replay/detail buffer once ClickHouse performance coverage is proven. This avoids introducing another partition tree for data that is no longer an analytical source. Until that short lifetime is enforced—or if a deployment requires more than 14 days of PostgreSQL span fallback—partition `trace_spans` monthly by `started_at` before material growth. Do not retain an unpartitioned, long-lived span table and assume ClickHouse reads alone will control PostgreSQL bloat.

### Legacy backup removal criteria

Remove `ingest_events_unpartitioned_backup` only when all of the following are recorded in one change ticket:

1. The live partitioned table and verified archives cover every required identity/time range from the backup; counts alone are insufficient.
2. ClickHouse schema v2 is ready, canonical checksum reconciliation passes, and all retained project/signal/hour watermarks are complete.
3. Application code, views, foreign keys, runbooks, and scheduled jobs have no dependency on the backup; `pg_stat_statements` shows no access for the full 30-day evidence window.
4. A fresh encrypted database snapshot exists, restore has been rehearsed, and the backup table's row count, time bounds, and checksum are attached to the ticket.
5. Free-disk headroom is adequate for catalog cleanup, the maintenance window is approved, and rollback ownership/expiry are explicit.

First revoke accidental application access and rename the table during a maintenance window. Observe for seven more days. Then take the final evidence snapshot and issue the explicit `DROP TABLE` with a short `lock_timeout`; table drops are not concurrent and must not be hidden in an application migration. Keep the external snapshot until the documented recovery expiry.

## S3 Archives

Set these in production to use S3 through Rails Active Storage:

```sh
ACTIVE_STORAGE_SERVICE=amazon
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=us-east-1
AWS_S3_BUCKET=<your-logister-archive-bucket>
LOGISTER_ARCHIVE_PREFIX=telemetry
```

S3-compatible services can also set `AWS_S3_ENDPOINT` and `AWS_S3_FORCE_PATH_STYLE=true`.

If uploads should stay on local disk while only telemetry archives use S3, leave `ACTIVE_STORAGE_SERVICE=local` and set:

```sh
LOGISTER_ARCHIVE_STORAGE_SERVICE=amazon
```

For the hosted Logister app, use the same env contract with a private bucket, public access blocked, default SSE-S3 encryption, a TLS-only bucket policy, and a lifecycle rule on `telemetry/` that transitions archives to colder storage and expires them after the chosen retention period. Self-hosters can replace only the bucket, credentials, region, endpoint, and prefix values.

Archive hot telemetry without deleting it:

```sh
bin/rails "logister:telemetry:archive[ingest_events,30,PROJECT_UUID]"
bin/rails "logister:telemetry:archive[trace_spans,30,PROJECT_UUID]"
```

Every non-dry archive is project-scoped and backed by a durable, checksummed
manifest. Untracked global archive uploads are disabled so permanent project purge
can enumerate and verify every object. Manifest objects use keys shaped like:

```text
telemetry/manifests/project=<project-uuid>/archive=<manifest-id>/<record-type>/part-<sequence>-<id-range>.jsonl.gz
```

Run with `DRY_RUN=true` to estimate object counts and bytes without uploading.

## Per-project Retention

Project owners can configure retention from **Project settings -> Data**:

1. Choose how long to keep activity events: logs, metrics, transactions, and check-ins.
2. Choose how long to keep trace spans.
3. Optionally choose how long to keep closed error groups. Leave this as forever to preserve resolved, ignored, and archived error history.
4. Enable **Archive retained data** to write gzip JSONL exports, then enable **Require archive before deletion** when cleanup must wait for a successful archive before removing old rows.

After the settings are saved, the retention form collapses into a summary row. Expand it when you need to change windows or archive behavior.

The **Archive Center** on the same Data page is the verification surface:

- **Overview** shows whether the project is not archiving, archiving without deletion protection, protected before deletion, or blocked by an archive problem.
- **Coverage** shows each retention scope, the latest cleanup cutoff, archived-through date, candidate count, archived rows, deleted rows, and status.
- **Catalog** lists recent archive runs, object keys, row counts, bytes, status, and failure messages.
- **Search Archives** searches current hot telemetry first and narrows candidate archive runs for older event evidence.

The production Sidekiq worker schedules `ProjectRetentionSweepJob` daily and enqueues one `ProjectRetentionJob` per project. Cleanup is project-scoped and uses `occurred_at` for ingest events, `started_at` for spans, and `last_seen_at` for closed error groups.

Run a safe dry run for every project:

```sh
bin/rails logister:telemetry:retention
```

Run a dry run for one project:

```sh
bin/rails "logister:telemetry:retention[PROJECT_UUID]"
```

Apply deletion only after reviewing the dry-run output:

```sh
DRY_RUN=false CONFIRM=retention bin/rails "logister:telemetry:retention[PROJECT_UUID]"
```

## Legacy Global Hot Pruning

`logister:telemetry:prune_hot` is disabled. Its global delete could bypass
per-project archive requirements and remove replay sources needed by pending,
processing, retrying, or terminally failed outbox deliveries. Use the
per-project retention task above; its dry-run output reports
`protected_by_delivery` before any confirmed deletion.

## Redis Retry Cleanup

If an older deploy left stale ClickHouse jobs in Sidekiq retries, inspect first:

```sh
bin/rails logister:sidekiq:prune_clickhouse_unknown_job_retries
```

Delete only the matched stale retry jobs:

```sh
DRY_RUN=false bin/rails logister:sidekiq:prune_clickhouse_unknown_job_retries
```
