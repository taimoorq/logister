# Redis, workers, and database pools

Logister can run with one Redis URL and one Sidekiq process. Larger or higher-availability installations should isolate durable job data from evictable cache data and scale worker queues independently.

## Redis roles

`REDIS_URL` is the backward-compatible fallback for every role. The dedicated settings below take precedence when present:

| Role | Environment variable | Data behavior |
| --- | --- | --- |
| Rails cache | `REDIS_CACHE_URL` | Evictable; a miss recomputes data. |
| Public and Devise rate limits | `REDIS_RATE_LIMIT_URL` | Ephemeral; failures log and fail open. |
| Sidekiq jobs and recurring schedules | `REDIS_SIDEKIQ_URL` | Durable; jobs must not be evicted. |

Different Redis database numbers on one server do not provide persistence, memory, failure, or eviction isolation. For a durable production topology, put `REDIS_SIDEKIQ_URL` on a separate Redis service or cluster configured with:

- `maxmemory-policy noeviction`;
- AOF or an appropriate RDB persistence schedule, with tested backups;
- automatic failover or a managed high-availability deployment;
- TLS and authentication when traffic leaves a private network.

The **Admin → Installation → Redis & jobs** diagnostic reports the observed eviction policy, persistence settings, primary/replica state, registered workers, queue ages, retry/dead counts, recurring-scheduler lateness, and database-pool sizing. An `unknown` value means the Redis provider denied its `INFO` or `CONFIG` command; verify that setting in the provider console.

## Queue topology

The checked-in `config/sidekiq.yml` consumes every workload queue plus the
`default` compatibility queue for Rails/framework jobs. It remains the
recommended small-install command, with equal queue weights so one busy queue cannot permanently exclude the others:

```sh
bundle exec sidekiq -C config/sidekiq.yml
```

At higher volume, run dedicated processes so slow integrations and maintenance cannot occupy projector capacity:

```sh
bundle exec sidekiq -q projector -c 5
bundle exec sidekiq -q analytics -c 3
bundle exec sidekiq -q notifications -q mailers -q default -c 3
bundle exec sidekiq -q integrations -q symbols -c 2
bundle exec sidekiq -q maintenance -c 1
bundle exec sidekiq -C config/sidekiq-archives.yml
```

The checked-in hosted profile uses `config/sidekiq-core.yml` for normal work and
`config/sidekiq-archives.yml` for archive work. The core profile reserves three of its five job threads for the projector and two for notifications, mailers, analytics, integrations, symbols, maintenance, and default jobs. Those general queues have equal positive weights. The archive profile consumes only
the `archives` queue at concurrency 1. This bounds concurrent compression,
object-storage, verification, and source-cleanup memory without delaying the
projector, notification, or mailer queues. Small self-hosted installations may
continue using the combined `config/sidekiq.yml`, which consumes both sets.

Keep every listed role running if you split the combined worker. The recurring scheduler seeds several future occurrences, reconciles missing schedules from the Sidekiq heartbeat, and records its latest start, completion, and failure in Sidekiq Redis so a hard-stopped execution does not silently break the chain.

Notification enqueueing is backed by PostgreSQL intents. If the notifications Redis
handoff fails after an error or monitor transition commits, the one-minute
`NotificationIntentSweepJob` retries it. A growing oldest pending intent age therefore
indicates a stopped notifications worker, repeated Redis enqueue failures, or a
poisoned target enqueue and should be alerted on; deleting Redis jobs is not a repair
because the PostgreSQL intent remains the recovery source of truth.

Sidekiq resolves concurrency before Rails boots. An explicit `-c` value therefore
wins for split roles; otherwise `config/sidekiq.yml` uses
`SIDEKIQ_CONCURRENCY`, defaulting to 5. The core profile divides that parsed total into two capsules. Set `SIDEKIQ_PROJECTOR_CONCURRENCY` to choose the projector share; it must leave at least one general thread. Without an override, two general threads are reserved (one when the total is two). The core profile rejects a total below two; use the combined profile for a one-thread installation. Worker heartbeats sum all capsule threads, so `DB_POOL=7` still covers the default five-thread core worker plus headroom.

## Database pool sizing

Set `DB_POOL` separately for each process. A Sidekiq process needs at least its concurrency plus two connections of headroom:

```text
DB_POOL >= actual Sidekiq process concurrency + 2
```

For example, the combined worker with `SIDEKIQ_CONCURRENCY=5` should use
`DB_POOL=7` or higher, while `sidekiq -c 3` needs at least `DB_POOL=5`. Web
processes can choose their own `DB_POOL` from their maximum thread count and any
application-specific headroom. Pool sizing is per OS process, so multiply it by
the number of web and worker processes when setting the PostgreSQL server
connection limit.

The concurrency-1 archive worker therefore needs `DB_POOL=3` or higher. Its
heartbeat appears separately in **Admin → Installation → Redis & jobs**. The
diagnostic uses raw Redis `SCAN`, so it works with both the Sidekiq Redis Client
adapter and the redis-rb client used by installation checks.

## Sampled pipeline timings

Production emits one payload-free `telemetry_pipeline` log summary for a sample of intake batches and projector drains. `LOGISTER_TELEMETRY_PROFILE_SAMPLE_RATE` defaults to `0.01`; set it to `0` to disable or temporarily increase it for a bounded investigation. Summaries include phase durations, SQL statement counts/timing, row/outcome counts, and exception class only. They never include SQL text, bindings, event contents, or client identifiers, and reporting is suppressed while writing the summary.

Check queue age together with durable delivery age and completed-versus-arriving work. A nonempty projector queue should not prevent general queues from advancing. Sidekiq 8 timestamps are measured in milliseconds; the installation diagnostic accepts these and older second timestamps. Retry/dead totals belong to the Redis service and may include other applications when Redis is shared.

## Enable ordered delivery claims

For operators with a large completed-delivery ledger, release 3.6.8 adds two small partial indexes for unfinished work. The migration builds them concurrently with a five-second lock-wait limit and a five-minute limit per statement. Keep a completed backup and check database I/O and intake health before migrating. A failed concurrent build can leave an invalid index; rerunning this migration removes its invalid residue and retries it. Existing claim indexes remain available.

After migration, verify that both rows below exist and have `indisvalid = true`:

```sql
SELECT c.relname, i.indisvalid
FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid
WHERE c.oid IN (
  to_regclass('public.idx_telemetry_deliveries_active_order'),
  to_regclass('public.idx_telemetry_deliveries_active_group')
);
```

Then set `LOGISTER_ORDERED_DELIVERY_CLAIMS=true` on core workers and restart them through the normal deployment process. The default is `false`. Compare sampled claim time, completed-versus-arriving deliveries, pending age, intake health, and the general queues. Eligibility, ordering, batch identities, row locks, retry fences, and purge exclusion are unchanged. Set the switch back to `false` to restore the old query; retain the additive indexes during application rollback. The release maintainer owns this switch until a normal-load window and recovery exercise justify removing the old path.

The [query benchmark](telemetry-claim-query.md) records the measured benefits, unfavorable cases, and additional write cost.
