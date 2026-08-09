# Telemetry data architecture

Logister uses PostgreSQL as the durable acceptance and control plane, ClickHouse as
the analytical serving plane, Redis in three independently configured roles,
and object storage as the archive plane. Background workers connect those stores
through a PostgreSQL outbox. No request depends on a distributed transaction.

## Decision summary

| Responsibility | System | Why |
| --- | --- | --- |
| Projects, users, credentials, notification state, retention policy | PostgreSQL | Transactional source of truth |
| Accepted-event identity, outbox, delivery attempts, purge/archive ledgers | PostgreSQL | Durable recovery and audit trail |
| Short PostgreSQL telemetry replay buffer | PostgreSQL | Product detail fallback and projector replay |
| Raw analytical facts and rollups | ClickHouse | Tenant/time scans, grouped exploration, and percentiles |
| Job queues and recurring schedule coordination | Dedicated Sidekiq Redis | Durable-enough queue semantics with a `noeviction` policy |
| Cache and circuit-breaker state | Dedicated cache Redis | Bounded, disposable acceleration state |
| Intake rate-limit counters | Dedicated rate-limit Redis | Failure policy and capacity independent of cache or queues |
| Verified cold telemetry archives | S3-compatible object storage | Inexpensive, immutable long-term retention |

BigQuery is not part of the product request path. It is a reasonable optional export
destination for customers that already use Google Cloud for cross-product BI, but it
would duplicate ClickHouse's analytical role while adding another delivery ledger,
freshness model, cost model, and failure domain. Revisit that decision only when a
concrete warehouse-export product requirement appears.

## Write path

1. A coarse source-IP guard runs before credential lookup. A single JSON envelope or
   gzip/NDJSON batch is bounded on wire bytes before parsing, then authenticated and
   normalized. Every batch envelope is an object with an object-valued event and a
   nonblank UUID client identifier.
2. PostgreSQL commits the replay-buffer record, idempotency key, outbox event, and
   required per-destination delivery intents in one transaction.
3. The response reports acceptance only after that commit. A duplicate identifier
   returns the original record and repairs any missing delivery intents while the
   replay source exists. After source retention, immutable ledger metadata supplies
   the same accepted identity and legacy identifier without recreating the source or
   introducing a projection intent that can no longer be fulfilled.
4. Projector workers lease deliveries in bounded batches. ClickHouse inserts carry a
   deterministic batch identity; other projectors perform idempotent grouping,
   deployment, and monitor updates.
5. Successful deliveries advance per-project, per-signal, hourly watermarks;
   terminal failures block completeness. Leases and retries remain inspectable in
   PostgreSQL.

This is an at-least-once pipeline with idempotent effects. A worker may repeat work
after an ambiguous acknowledgement, but repetition must not create a second logical
fact or inflate an aggregate.

Error-group and check-in transitions use the same boundary for notifications.
PostgreSQL commits a uniquely keyed `notification_intents` row in the transaction
that creates the group occurrence or monitor transition. A Sidekiq enqueue after
commit is only an accelerator: the recurring notification-intent sweep reclaims
pending or expired leases, so a Redis outage between commit and enqueue cannot lose
the alert. Frequent-error observations are likewise committed to
`notification_evaluations` with the group occurrence and swept independently.

Monitor intents carry a persisted transition UUID and expected current state. The
notification job locks and revalidates both before dispatch, which suppresses stale
alerts after a later transition while giving every failure/recovery cycle its own
delivery deduplication identity. Delivery recovery also reloads the project lifecycle
and skips mail after archival or a purge tombstone.

## Read path

Each analytical capability asks the coverage service whether every requested project
× signal × overlapping hour has an exact, correctly paired destination watermark.
Complete ranges use ClickHouse; one missing or malformed bucket routes the whole
capability to PostgreSQL. Verified-zero seals cover sparse signals for recently active
tenants, while dormant tenants without evidence fail closed. Query exceptions may
trigger fallback, but a successful ClickHouse connection alone never proves that its
data is complete. Matching PostgreSQL and ClickHouse after PostgreSQL retention is not
historical proof; manual backfill publishes absolute watermarks only from a declared,
externally verified retained-source baseline.

Raw ClickHouse tables are at-least-once append/replay logs. `event_facts_v2` and
`span_facts_v2` select one stable projector version for each project and telemetry UUID;
all Dashboard, Explorer, Insights, custom metric, attribute catalog, and performance
queries use those logical facts or views derived from them. The projector supplies an
explicit canonical UUID-as-`UInt128` checksum, avoiding ClickHouse UUID storage-endian
reinterpretation. Minute/hour views are ordinary logical views over deduplicated facts,
so replay cannot permanently inflate counts, averages, or percentile inputs.

Responses and diagnostics should expose the selected source and its delivery lag.
After a dual-read comparison window proves equivalence, PostgreSQL telemetry
retention and redundant indexes can be reduced independently by signal.

An hourly bounded sealer re-verifies the two most recently closed hours for tenants
with recent source/outbox activity and emits zero seals for their sparse signals. A
daily cleanup removes inactive watermarks beyond the 90-day ClickHouse/read horizon;
active delivery buckets remain until resolved. This bounds the cross-product without
eagerly materializing hours for dormant projects. Raw ClickHouse facts retain 120
days, preserving a 30-day TTL margin beyond the maximum authorized read/watermark
horizon.

During that comparison window, a deterministic sample of complete reads executes a
normalized PostgreSQL shadow query and emits a reconciliation notification. The
ClickHouse and PostgreSQL adapters return the same typed intermediate contract before
hash comparison; PostgreSQL recent-event detail remains available even when analytical
summaries and series come from ClickHouse.

## Queue topology

The combined worker process consumes every queue for small installations. Larger
installations can scale roles independently:

- `projector`: outbox delivery and ClickHouse projection;
- `analytics`: backfills, reconciliation, and analytical maintenance;
- `notifications`: notification evaluation and delivery recovery;
- `integrations`: App Store, Google Play, and Cloudflare imports;
- `maintenance`: retention, archive, purge, and partition maintenance;
- `symbols`: symbol artifact processing;
- `mailers`: Action Mailer delivery.

The combined worker consumes `default` last as a compatibility safety net for
Rails/framework jobs; the split notifications/mailers process consumes it too.
Logister-owned jobs use an explicit workload queue.

Database pool size must cover worker concurrency plus operational headroom. Queue
Redis must use persistence, high availability appropriate to the installation, and
`maxmemory-policy noeviction`; cache eviction must never be able to delete jobs.

## Retention, archive, and deletion

Archives start with a durable manifest containing immutable record identities,
source bounds, row and byte counts, and checksums. PostgreSQL rows are deleted only
after the uploaded object is read back and verified. Inspect, retry, replay, restore,
and orphan-cleanup operations use the same manifest.

Replay-buffer retention anti-joins each exact event/span identity against its outbox
deliveries. A source row is ineligible for archive-driven or direct deletion while
any delivery is pending, processing, retrying, or terminally failed. Batch deletion
locks the matching idempotency keys, outboxes, deliveries, and source rows in that
order before clearing workflow references. Source deletion and the durable
`source_retired_at` marker commit atomically; late destination repair observes that
marker and refuses to create source-dependent work. Later retention runs retry
protected rows after delivery completion.

Source UUID semantics are project-scoped. `trace_spans` enforces `(project_id, uuid)`
with a unique index. PostgreSQL cannot enforce the same cross-partition uniqueness on
`ingest_events` without including the range key (`occurred_at`), so its composite
lookup index is intentionally non-unique; the project-scoped idempotency ledger plus
sorted transaction-scoped advisory locks is the canonical concurrency boundary.

Project deletion is a visible state machine. Intake is revoked first, then a purge
ledger removes archive objects, ClickHouse raw facts and rollups, PostgreSQL telemetry
and control rows, and finally Redis-derived state. Keeping PostgreSQL until external
cleanup completes preserves owner visibility and the durable authorization context.
Completion is recorded only after every configured store has been verified empty. A
failed step remains retryable.

## Rollout rules

- Deploy additive schema and configuration fallbacks before enabling new writers.
- Create outbox intents while old synchronous derivations still exist, then prove
  projector coverage before removing request-path work.
- Enable ClickHouse reads capability by capability behind completeness gates.
- Treat index removal, backup-table removal, and shorter replay retention as separate
  production operations backed by observed query and coverage data.
- Roll back by changing writer/read modes; do not require restoring already deleted
  telemetry during an application rollback.

## Operational signals

At minimum, alert on oldest pending telemetry delivery and notification-intent age,
lease-expiration count, terminal delivery failures, per-destination coverage gaps,
ClickHouse circuit state, queue age and dead/retry counts, recurring-schedule
lateness, default-partition rows, database pool headroom, archive verification
failures, and incomplete project purges.
