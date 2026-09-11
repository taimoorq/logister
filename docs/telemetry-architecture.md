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

### Lock boundaries under ingestion load

Batch acceptance accumulates the count and UUID checksum of newly created delivery
intents, then updates hourly watermarks in one sorted upsert immediately before the
acceptance transaction commits. Repeated identities contribute only when repairing
a missing intent. Source records, intents, and watermarks still commit or roll back
together. A projector cannot see an intent before its accepted count is durable.

Accepted and delivered progress use atomic increments that recompute completeness
from the resulting counts, checksums, and terminal-failure count in the same SQL
statement. Existing buckets do not require an exception-driven insert, row reload,
and separate completion update for each envelope. The terminal-failure, replay,
empty-seal, backfill, and cleanup paths retain their existing safety boundaries.

New delivery claims use `FOR UPDATE OF telemetry_deliveries SKIP LOCKED`. The joined
project and outbox rows are filters, not claim targets; locking them would serialize
otherwise independent deliveries for the same project. A batch with an existing
ClickHouse deduplication key first acquires a transaction advisory lock for that
batch and locks its due deliveries together in ID order. It must not be split by
competing claimers into separate writes using the same deduplication token.

ClickHouse writes hold a project row with `FOR SHARE` until the external call ends.
Concurrent writers and ingestion foreign-key checks can proceed, while the purge
request's exclusive project lock must wait. After a purge tombstone commits, a new
writer rechecks it under the shared lock and refuses the write. Do not release this
fence before the external call or replace it with an unlocked lifecycle check.
These compatibility rules follow PostgreSQL's [row-lock conflict matrix](https://www.postgresql.org/docs/17/explicit-locking.html#LOCKING-ROWS).

Validate lock changes with real independent PostgreSQL connections in
`spec/services/logister/telemetry_contention_spec.rb`. The suite holds an external
write open, verifies ingestion and another projector can advance, and verifies a
purge cannot pass that write. Batch specs also check counter-query cost, duplicate
retries, invalid-envelope rollback, and failure of the final counter write.

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

### Partition-scoped grouping references

Error grouping updates the accepted source event using its project, ID, and canonical `occurred_at`, and uses the same reference when reloading after a duplicate race. A backlink update must match exactly one row; otherwise the grouping transaction rolls back. Latest-event timestamp synchronization uses a supplied partition reference and retains a tenant-scoped ID lookup for legacy callers that change only an ID. Do not replace these predicates with ID-only writes: source IDs can repeat across timestamp partitions.

### Durable projection payloads and acknowledgements

Release 3.6.10 introduces the opt-in `LOGISTER_BATCHED_PROJECTION` path. It preloads source rows by project, record type, ID, and canonical timestamp, then commits each bounded ClickHouse body's compressed NDJSON, SHA-256, ordered delivery membership, and immutable deduplication key before sending it. One `telemetry_projection_batches` row represents one external body, with at most 200 members and 1 MiB plus the legacy trailing-newline allowance. The HTTP client sends verified bytes directly; retries do not rebuild them from changing source data or parse and reserialize numbers.

Release 3.6.11 adds optional bounded admission and cooperative run budgets without changing the accepted-work authority. Native queue hints are coalesced behind one waiting marker, while unique attempt owners admit three drainers and PostgreSQL retains per-delivery fencing. Periodic recovery handles lost hints and expired owners. Unstarted budget yields refund the claim attempt; attempted/ambiguous writes keep their durable identity. See [projector recovery](telemetry-projector-recovery.md) for the complete lifecycle, failure cases and limits.

Batch assignment locks and checks every requested lease before assigning any key. Acknowledgement locks delivery IDs in order, transitions only currently owned processing rows, and updates the exact corresponding watermark counts/checksums in the same transaction. Stale or already completed rows contribute zero. The batch payload is deleted with the final acknowledgement. Daily ledger cleanup removes payloads left after compatible older workers complete their rows; incomplete and terminal batches remain available for recovery. Project deletion cascades to the payload table.

The project shared lock still spans the external insert, preserving the purge fence. Retention and ledger cleanup protect every member while any member of its project/destination/batch remains incomplete, including completed members needed to reconstruct legacy partial acknowledgements. Batch records contain the same sensitive telemetry as their source and must use the same database access and backup controls; they are temporary replay data, not a new archive.

Legacy batches did not store original HTTP bytes. Their retry path reconstructs the full original member set, verifies its deterministic UUID digest, and includes previously completed rows in the external body while counting only newly acknowledged deliveries. Missing membership, changed source/outbox timestamps, changed project service fallback, suppressed members, and oversize groups stop inspectably instead of silently changing the body. This cannot retroactively prove that an older serializer emitted identical bytes; investigate historical unverifiable batches rather than inventing a new deduplication key.

The feature defaults off. Disabling it stops new payload creation but continues to consume existing persisted bodies. Drain those records before downgrading to a release before 3.6.10. The schema rollback refuses to remove a nonempty payload table. See [worker operations](redis-worker-operations.md#enable-batched-projection) for activation and rollback.
