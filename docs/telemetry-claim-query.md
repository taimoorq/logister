# Delivery claim query measurements

This note helps maintainers assess the ordered active-delivery query introduced in 3.6.8. Enablement and rollback instructions are in [Redis and worker operations](redis-worker-operations.md#enable-ordered-delivery-claims).

## Dataset and method

The disposable benchmark used PostgreSQL 17.7 in a local container with a 2 GB memory limit and default database settings. It contained two million delivery rows and matching outbox rows, fifteen projects, 99% completed deliveries, and 80% of records in one project. The remaining twenty thousand deliveries mixed pending, retrying, active leases, and expired leases. Outbox timestamps spanned one hour, with metric/error signal skew. Baseline indexes matched the application schema.

Each query was measured three times with `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`. Claim candidates retained the outbox/project joins and `FOR UPDATE OF telemetry_deliveries SKIP LOCKED`; each measurement rolled back. The table reports median execution time. These local measurements demonstrate access patterns, not production latency guarantees. Caches were not flushed, and the large baseline outbox scan continued reading blocks absent from shared buffers.

| Query | Original | Ordered active query |
| --- | ---: | ---: |
| Oldest eligible seed | 12.8 ms | 0.055 ms |
| Fresh 200-row hot-project group | 590.5 ms | 0.694 ms |

The active order index occupied 632 KB and the fresh group index 1,344 KB. The seed used four shared-buffer hits. The fresh candidate query used 1,211 hits, versus roughly 38,000 physical reads in the baseline's outbox scan.

## Query decision and limitations

Two literal active-state partial predicates make completed rows irrelevant to the ordered indexes. The new eligibility expression chooses `lease_expires_at` for processing rows and `available_at` for pending/retrying rows. This preserves the original eligibility boundary, including null leases, while avoiding the overlapping status estimates of the original OR expression. Ordering stays `available_at, id`, including for expired leases.

Simply adding the indexes did not reliably improve the old OR query. Adding a redundant active-status filter helped the seed but still made the fresh query inspect all 15,900 eligible hot-project sources. The CASE expression allowed the fresh claim to stop after the requested rows. Separate claim branches and a changed locking protocol were unnecessary for this improvement.

A forced generic prepared plan still used the active seed index, but the hot-project candidate plan read more rows: about 23 ms. Do not claim every prepared plan takes less than a millisecond. Skew and growing active work still require observation; the active indexes are not a constant-time guarantee.

Additional checks compared the complete selected ID sequence with the original query for future work, expired leases whose availability is in the future, all projects purging, and an empty eligible set. Selections matched. Across these cases the seed measured about 0.07–7 ms and the fresh candidate query about 0.5–21 ms after scenario updates. Unit tests independently cover all status/attempt/time boundaries, and connection-level tests preserve disjoint fresh claims, intact assigned retries, and the purge fence.

## Migration and write cost

The actual migration was rehearsed against the same PostgreSQL 17.7 dataset. A held writer forced its five-second lock timeout and left an invalid concurrent index. After releasing the writer, rerunning the migration removed the invalid residue and built both valid indexes; a further run succeeded without rebuilding them. Both session timeout settings were restored.

A 200-row processing transition produced approximately 202 KB of WAL without these indexes and 238 KB with them, an 18% increase in that sample. This is the explicit tradeoff for cheaper reads; elapsed write times were cache-sensitive and do not establish faster writes. Keep the previous indexes for rollback until production evidence justifies any removal.
