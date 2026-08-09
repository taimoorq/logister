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
low-priority `default` compatibility queue for Rails/framework jobs. It remains the
recommended small-install command:

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
```

Keep every listed role running if you split the combined worker. The recurring scheduler seeds several future occurrences, reconciles missing schedules from the Sidekiq heartbeat, and records its latest start, completion, and failure in Sidekiq Redis so a hard-stopped execution does not silently break the chain.

Notification enqueueing is backed by PostgreSQL intents. If the notifications Redis
handoff fails after an error or monitor transition commits, the one-minute
`NotificationIntentSweepJob` retries it. A growing oldest pending intent age therefore
indicates a stopped notifications worker, repeated Redis enqueue failures, or a
poisoned target enqueue and should be alerted on; deleting Redis jobs is not a repair
because the PostgreSQL intent remains the recovery source of truth.

Sidekiq resolves concurrency before Rails boots. An explicit `-c` value therefore
wins for split roles; otherwise `config/sidekiq.yml` uses
`SIDEKIQ_CONCURRENCY`, defaulting to 5. The Rails initializer does not replace the
parsed value, and worker heartbeats report that actual process concurrency.

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
