# Project page performance investigation

Production was inspected with read-only Fly logs, PostgreSQL statistics and
`EXPLAIN` on 2026-09-30 around 02:04–02:09 UTC. Diagnostic SELECTs used a short
statement timeout. No indexes, configuration, source records or running jobs
were changed in production.

## Observed bottleneck

- Production was running 3.8.0 at `dbe77db`, not the merged navigation/setup PR
  #113 (`ba14ed4`). Its release workflow failed because `VERSION` was still
  3.8.0 while the immutable v3.8.0 tag referred to the earlier commit.
- Activity returned in 18.5 seconds; two release-health frames took 39.4 and
  43.4 seconds. Almost all elapsed time was Active Record time. Project overview
  requests ranged from 1.3 to 5.5 seconds in the sample.
- The shared PostgreSQL host reported about 62% full I/O pressure over 60
  seconds and 71% over 10 seconds, with effectively zero CPU pressure. This is
  host-level evidence; other databases on that host can also contribute.
- The September event partition held approximately 2.1 million estimated live
  rows, a 2.3 GB heap, and 3 GB of indexes. The database had 512 MB of shared
  buffers on a 2 GB machine. Disk was 63% used, so this was not a full disk.
- Activity cursor, release-expression and receipt indexes were present.
  PostgreSQL selected the Activity cursor index and receipt index-only scans.
  Adding duplicate indexes would increase ingestion and storage work.
- Release discovery scanned recent telemetry; its two subsequent count queries
  dropped the time bound and visited all retained partitions.
- A retention archive's filtered `MAX(id)` was active after 29 seconds, waiting
  on data-file I/O. Its predicate evaluated delivery protection across the
  selection before any bounded archive enumeration could begin.

## Changes

- Build PostgreSQL dashboard project/type/count/latest signals with one grouped
  scan instead of four. Find setup candidates with receipt existence checks,
  without fetching the latest timestamp from every partition.
- Discover releases and count their events in one scan over the requested
  lookback. The release-health page explicitly labels event counts as the last
  45 days; introduced/regressed issue counts still describe retained history.
  Cache the shared frame result for one minute.
- Keep dashboard/project cache keys stable across time buckets so TTL and
  stale-entry refresh protection can work. A failing computation is propagated
  once; cache failures do not repeat an already completed database computation.
- Navigation checks monitor existence without calculating mobile session,
  mapping or symbol coverage. Narrow setup checks load only the requested
  evidence; receipt checks select a timestamp without event JSON.
- Capture archive insert fences from the indexed source-table maximum. Apply
  tenant, time, event-type and delivery-protection predicates during enumeration
  as before. The replacement maximum used 21 partition index-only probes and
  took 105 ms in a bounded production SELECT. This is a query measurement, not
  a claim that the whole archive or a page now completes in that time.

No schema migration is required. Cold release summaries still aggregate the
lookback; these changes reduce repeated work but do not remove the need to
address database I/O capacity and analytics routing.

## Release and operational follow-up

1. Release the prepared 3.9.0 version, changelog, OpenAPI version and release set;
   do not move the existing v3.8.0 tag. Verify the deployed revision after the
   release. The observations above cannot establish a regression from code
   that was not deployed.
2. Compare Activity, overview, dashboard and release-health cold/warm timings,
   database I/O pressure, ingestion latency and archive progress after release.
   Run each cold page once initially to avoid concurrent aggregate stampedes.
3. Enable `pg_stat_statements` through the database's normal maintenance path
   and collect a representative normalized query profile. It was not enabled
   during this investigation, so historical top-query attribution is limited.
4. Check volume IOPS and latency, archive concurrency and working-set memory.
   If pressure persists, evaluate database memory/storage capacity or workload
   isolation using measurements. More web CPU does not address this sample's
   bottleneck. Old partitions with zero statistics are not proof they are empty;
   investigate statistics and retention before any cleanup.
5. Verify ClickHouse coverage and routing for heavy dashboard/Explorer analytics
   using [the existing runbook](telemetry-storage-retention.md). Dual write alone
   does not move reads off PostgreSQL. Release-health aggregation remains a
   PostgreSQL path and may warrant a separate rollup at larger scale.

Rollback is an application revert; no data or index reversal is needed.
