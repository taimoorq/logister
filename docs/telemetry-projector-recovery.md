# Bounded projector execution and recovery

Release 3.6.11 adds `LOGISTER_BOUNDED_PROJECTOR`, default `false`. The PostgreSQL
delivery ledger remains the source of accepted work and completion. Redis holds
disposable wake hints and admission state. Enable this after the ordered claim
and persisted-payload releases have passed their separate rollout checks.

## Ownership and recovery

| Boundary | Identity and transition | Recovery |
| --- | --- | --- |
| Accepted telemetry | Existing tenant-scoped source, outbox and delivery IDs commit atomically | The periodic projector sweep discovers due deliveries even when enqueue fails |
| Wake hint | A generation advances on every wake; at most one waiting native ActiveJob carrier is reserved | An old reservation is cleared only when a bounded queue scan proves its carrier absent |
| Drainer | Up to three Redis owners; each execution attempt gets a new UUID, including retries of the same job ID | Redis TIME expires abandoned owners after 90 seconds; late renewal/release cannot change a successor |
| Claimed delivery | Existing PostgreSQL token and two-minute lease | Renew the complete owned group before writing; do not renew expired or changed tokens |
| External batch | Persisted original bytes, membership, checksum and deduplication key | Retry the saved body; acknowledge only owned rows in the watermark transaction |
| Voluntary yield | Wholly unstarted owned rows return to pending with one claim attempt refunded | Preserve any assigned batch identity and body; follow-up draining resumes them |
| Attempted failure | Existing retry/terminal status and attempt policy | If bookkeeping reaches the deadline, remaining attempted rows retain their leases for recovery |

The waiting marker has no short TTL. A worker outage must not generate another
job every few seconds while its carrier is still queued. Recovery scans at most
1,001 queue entries and retains the marker when a scan is too large or malformed.
Existing argument-free hints can enter a free slot but cannot clear a newer
carrier's marker. No queue trimming is required.

The pending generation closes the final-empty race: work accepted after a
drainer's last empty query still causes a follow-up when the drainer releases.
Normal operation has at most three admitted drainers and one waiting hint.
Redis state loss or a producer paused between its final reservation check and
enqueue can temporarily produce duplicate hints. Admission and PostgreSQL
ownership fences make those hints safe; this is not an exactly-once queue.

A retryable result or an unexpected drainer error starts a ten-second admission
cooldown. Bounded jobs do not also ask Sidekiq to retry the disposable hint.
PostgreSQL retry availability/leases and the one-minute startup/heartbeat
recovery sweep own retries. Recovery timing also depends on worker heartbeat
cadence and existing delivery leases. Redis failures never fall back to one
enqueue per intake request. Failure logging is throttled and contains only the
error class; this feature does not create monitors or emails.

## Budgets and evidence

| Budget | Basis | Failure behavior / review |
| --- | --- | --- |
| Three drainers, one waiting hint | Matches the default core capsule's three projector slots; general work retains two slots | Global across the app's Redis namespace; review before changing the worker split or scaling replicas |
| 25 seconds per run | Retains the prior job's runtime target, now checked before claims and safe units | Finish an in-flight unit, then yield. This is a cooperative budget, not a hard preemptive deadline |
| Ten fresh synchronous deliveries / expired final-lease transitions | Initial hypothesis to avoid claiming 200 expensive grouping/indexing units at once | Persisted retry groups are never truncated; compare grouping duration and throughput during rollout |
| 200 rows / approximately 1 MiB per external batch | Existing payload contract | Retain exact original membership/bytes across retries |
| 90-second admission / 120-second delivery leases | Admission gives ample headroom over a normal 25-second run and bounded dependency waits | Check admission between units and force renewal before external writes; review expired leases under peak load |
| Five-second SQL statement / one-second lock waits | Initial worker isolation budgets | Applied only while draining, restored on the connection afterward; canceled operations follow delivery recovery |
| HTTP open 2s, read 5s, write 5s; implicit retries disabled | Explicit dependency I/O limits | Ambiguous insert failures return to the durable delivery protocol |
| Insert response 10s / 1 MiB | Initial response budget; inserts should return a small acknowledgement | Check between received chunks and close failed connections; a read may overrun by its I/O timeout |
| Ten-second failure cooldown; one-minute recovery gate | Initial outage-load and recovery tradeoff | New telemetry may wake after cooldown; otherwise periodic recovery catches accepted work |

Network timeouts apply to I/O operations. A slow unit can overrun the cooperative
run target; no asynchronous Ruby timeout exception interrupts an insert or an
acknowledgement. SQL limits are scoped connection settings (preserving stricter existing limits), not an outer
transaction: the payload must commit before the external call.

The release maintainer owns these initial limits. Compare normal and peak load
before changing them: arrival/completion rates, oldest due age, per-phase sampled
latency, yielded rows, lease conflicts, terminal failures, connection waits,
general queue progress, worker memory and database I/O. A falling queue count
alone does not prove delivered coverage.

## Verification

Run the ordinary backend suite against disposable PostgreSQL and Redis. The
focused admission tests start their own Redis servers and verify concurrent wake
floods, saturated owners, final-empty races, orphan reservations, legacy hints,
stale owners, Redis loss and outage cooldown. PostgreSQL tests verify yield
refunds, exact retry membership, ownership renewal and atomic acknowledgement.

The real process recovery test also needs an isolated local ClickHouse 24.8
server with the test-only credentials `logister_test` / `test-only`:

```sh
RAILS_ENV=test RECOVERY_CLICKHOUSE_URL=http://127.0.0.1:8123 \
  bundle exec rspec spec/integration/telemetry_recovery_spec.rb
```

Set `DATABASE_URL` and `REDIS_URL` to dedicated test services first. The test
creates and removes its own ClickHouse database, Redis server and Sidekiq
processes. It kills the OS worker after external success and before local ACK,
changes source data, advances lease deadlines and restarts recovery. It verifies
exact saved bytes, logical facts and PostgreSQL counts/checksums. A deliberately
new deduplication token also verifies logical facts remain correct beyond the
provider's finite insert-deduplication window. CI runs this test with its own
ClickHouse service; local runs without the URL explicitly skip it.

## Enable and roll back

1. Deploy 3.6.11 with the flag off. Finish the separate ordered-claim and batched
   projection activation checks first, with no incompatible older workers.
2. Enable `LOGISTER_BOUNDED_PROJECTOR=true` consistently on intake and worker
   processes, then use the normal rolling restart. Existing scheduled hints
   drain safely. Mixed older producers temporarily retain their old wake rate.
3. Verify all core workloads progress and that the recovery sweep runs even
   when intake is quiet. Compare the metrics above and inspect bounded Redis
   state without dumping payloads:

   ```ruby
   keys = Logister::TelemetryProjectorAdmission::KEYS
   Sidekiq.redis do |redis|
     puts({ waiting: redis.call("EXISTS", keys[1]) == 1, owners: redis.zcard(keys[2]),
            cooldown_seconds: redis.ttl(keys[3]) }.to_json)
   end
   ```

   Owner count may include recently expired entries until the next admission
   operation removes them. It is not a replacement for Sidekiq worker status.
4. Stop promotion on inconsistent watermarks, altered retry bodies, tenant/purge
   failures, rising terminal failures or sustained intake/general queue
   degradation. Disable `LOGISTER_BOUNDED_PROJECTOR` and restart normally to
   restore the earlier scheduling path. Leave payload records and batch keys
   intact; the [projection rollback rules](redis-worker-operations.md#enable-batched-projection)
   still apply before downgrading below 3.6.10. Do not clear delivery or Sidekiq
   queues as a rollback step.
