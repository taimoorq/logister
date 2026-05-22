# Telemetry Storage and Retention

Logister uses PostgreSQL for app data and hot event detail, Redis for cache and Sidekiq, ClickHouse for analytics rollups, and optional S3 storage for cold telemetry archives.

## ClickHouse Readiness

`/health/clickhouse` now checks that the required analytics tables and materialized views exist, not only that ClickHouse answers `SELECT 1`.

Use the idempotent schema loader after provisioning a self-hosted ClickHouse database:

```sh
bin/rails logister:clickhouse:schema:load
bin/rails logister:clickhouse:schema:status
```

The schema lives in `docs/clickhouse_schema.sql` and includes raw event/span tables plus one-minute rollups.

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
bin/rails "logister:telemetry:archive[ingest_events,30]"
bin/rails "logister:telemetry:archive[trace_spans,30]"
```

Each archive object is compressed JSONL at:

```text
telemetry/<record_type>/year=YYYY/month=MM/day=DD/<exported_at>-<id-range>.jsonl.gz
```

Run with `DRY_RUN=true` to estimate object counts and bytes without uploading.

## Hot Pruning

After verifying archives, prune non-error hot telemetry and spans with an explicit confirmation:

```sh
CONFIRM=prune bin/rails "logister:telemetry:prune_hot[30]"
```

This intentionally keeps error events and grouped error details in PostgreSQL while trimming high-volume logs, metrics, transactions, check-ins, and trace spans.

## Redis Retry Cleanup

If an older deploy left stale ClickHouse jobs in Sidekiq retries, inspect first:

```sh
bin/rails logister:sidekiq:prune_clickhouse_unknown_job_retries
```

Delete only the matched stale retry jobs:

```sh
DRY_RUN=false bin/rails logister:sidekiq:prune_clickhouse_unknown_job_retries
```
