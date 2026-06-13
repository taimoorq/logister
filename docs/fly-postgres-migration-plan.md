# Fly Postgres Migration Plan

Created: 2026-06-13

## Goal

Move Logister production data from Prisma Postgres to a low-cost, self-managed Fly Postgres instance, and use the same Postgres machine for three additional app databases.

This setup is intentionally for dev, hobby, and non-critical production use. It optimizes for cost and simplicity, not high availability.

## Current Prisma Usage Snapshot

Usage reported for 2026-06-01 through 2026-06-13:

| Project | Operations | Storage |
| --- | ---: | ---: |
| Logister | 5,942,493 | 3.67 GiB |
| TQ | 3,488,170 | 0.18 GiB |
| africa-unfiltered | 1,113,445 | 0.02 GiB |
| Follow Trades Production | Not reported in operation split | 0.29 GiB |
| Total | 10,544,108 | 4.16 GiB |

Estimated monthly total at the same pace: about 24.3M operations/month.

Average query rate for the whole account: about 9.4 operations/second.

## Target Fly Shape

| Setting | Value |
| --- | --- |
| Fly app name | `shared-pg-iad` |
| Region | `iad` |
| Cluster size | 1 machine |
| CPU | `shared-cpu-2x` |
| Memory | `2048 MB` |
| Volume | `20 GB` |
| Postgres type | Fly self-managed Postgres |

Expected monthly cost is roughly the VM cost plus 20 GB of volume storage. This is much cheaper than operation-metered database hosting, but it creates one shared failure domain for all four apps.

## Monthly Cost Comparison

Prices checked on 2026-06-13 against the official Fly.io and Supabase pricing docs.

Assumptions:

- The four databases together use about 4.16 GiB today, with room for growth inside the 20 GB Fly volume.
- The target Fly setup is self-managed Fly Postgres in `iad`, not Fly Managed Postgres.
- The Supabase comparison uses the Pro plan, because production projects should not rely on the Free plan's pause and size limits.
- Network egress is ignored for the baseline comparison. Fly app-to-database traffic is free when the apps stay in the same region. Supabase Pro includes 250 GB/month of uncached egress before overage.

| Option | Monthly cost | What is included | Tradeoff |
| --- | ---: | --- | --- |
| Fly self-managed Postgres target | ~$14.39 | `shared-cpu-2x` / 2 GB VM in `iad` (~$11.39) + 20 GB Fly volume (~$3.00) | Cheapest monthly bill, but backups, upgrades, monitoring, HA, and restore testing are our responsibility. |
| Supabase Pro, one consolidated Micro project | ~$25.00 | One Supabase project, Micro compute covered by the included compute credit, 8 GB included disk | Managed backups and platform tooling, but only 1 GB RAM and awkward isolation if multiple unrelated apps share one project. |
| Supabase Pro, one consolidated Small project | ~$30.00 | One Supabase project on Small compute: 2 GB RAM, closer to the Fly target | Still one shared project/database boundary; better RAM match than Micro. |
| Supabase Pro, four separate Micro projects | ~$55.00 | Four isolated Supabase projects on default Micro compute: $25 Pro + $40 compute - $10 credit | Cleaner isolation and managed daily backups, but about 3.8x the target Fly self-managed cost. |
| Supabase Pro, four separate Small projects | ~$75.00 | Four isolated Supabase projects with 2 GB RAM each | More isolated capacity than the Fly target and likely unnecessary for the three small databases. |
| Fly Managed Postgres Starter | ~$77.60 | Fly Managed Postgres Starter 2 GB plan ($72) + 20 GB managed storage ($5.60) | Managed HA/backups/support, but much more expensive than the self-managed Fly target. |

Cost call: for this dev, hobby, and non-critical production footprint, the self-managed Fly target is the best monthly-cost option. Supabase is the better operational-simplicity option if we are willing to pay more for managed backups and platform operations. The fair Supabase shape for four separate apps is the four-project Micro setup at about $55/month; the one-project Supabase options are cheaper, but they trade away clean app isolation.

## Databases And Roles

Create one database and one login role per app.

| App | Database | Role |
| --- | --- | --- |
| Logister | `logister_production` | `logister_app` |
| TQ | `tq_production` | `tq_app` |
| africa-unfiltered | `africa_unfiltered_production` | `africa_unfiltered_app` |
| Follow Trades | `follow_trades_production` | `follow_trades_app` |

Do not reuse a superuser in app runtime configuration.

## Provisioning

Create the Postgres app:

```bash
fly postgres create \
  --name shared-pg-iad \
  --region iad \
  --initial-cluster-size 1 \
  --vm-cpu-kind shared \
  --vm-cpus 2 \
  --vm-memory 2048 \
  --volume-size 20
```

Connect as the default Postgres admin:

```bash
fly postgres connect -a shared-pg-iad -d postgres
```

Create the roles and databases:

```sql
CREATE ROLE logister_app LOGIN PASSWORD 'replace-me';
CREATE DATABASE logister_production OWNER logister_app;

CREATE ROLE tq_app LOGIN PASSWORD 'replace-me';
CREATE DATABASE tq_production OWNER tq_app;

CREATE ROLE africa_unfiltered_app LOGIN PASSWORD 'replace-me';
CREATE DATABASE africa_unfiltered_production OWNER africa_unfiltered_app;

CREATE ROLE follow_trades_app LOGIN PASSWORD 'replace-me';
CREATE DATABASE follow_trades_production OWNER follow_trades_app;
```

After creation, rotate the placeholder passwords into strong generated values.

## Logister Migration Rehearsal

Use the Prisma direct Postgres URL as the source. Avoid pooled URLs for `pg_dump`.

Open a local tunnel to the Fly Postgres app:

```bash
fly proxy 15432:5432 -a shared-pg-iad
```

Dump from Prisma:

```bash
pg_dump -Fc --no-owner --no-acl "$PRISMA_LOGISTER_DATABASE_URL" \
  > logister-prisma-precutover.dump
```

Restore into Fly:

```bash
pg_restore --verbose --clean --if-exists --no-owner --no-acl \
  --dbname "postgres://logister_app:PASS@localhost:15432/logister_production?sslmode=disable" \
  logister-prisma-precutover.dump
```

Prisma Postgres dumps can include the Prisma-only extension `prisma_postgres`. Stock Fly Postgres does not have that extension. If restore fails on `CREATE EXTENSION prisma_postgres`, build a filtered restore list and replay the dump without those entries:

```bash
pg_restore -l logister-prisma-precutover.dump \
  | grep -v "prisma_postgres" \
  > logister-restore-no-prisma-extension.list

pg_restore --verbose --clean --if-exists --no-owner --no-acl \
  --exit-on-error \
  --use-list logister-restore-no-prisma-extension.list \
  --dbname "postgres://logister_app:PASS@localhost:15432/logister_production?sslmode=disable" \
  logister-prisma-precutover.dump
```

Run Logister verification:

```bash
DATABASE_URL="postgres://logister_app:PASS@localhost:15432/logister_production?sslmode=disable" \
  RAILS_ENV=production \
  bundle exec rails db:migrate:status
```

Also verify:

- `schema_migrations` matches Prisma.
- `pgcrypto` and `pg_trgm` extensions exist.
- Row counts look plausible for high-value tables.
- Sign-in works.
- Project creation works.
- API key generation works.
- One test ingest event succeeds.
- Sidekiq starts and can read/write expected tables.

## Cutover Runbook

Use a short maintenance window.

1. Confirm the rehearsal restore and verification passed.
2. Disable or pause external writers if applicable.
3. Stop the Logister Fly worker and app:

```bash
fly scale count 0 -g worker -a logister-org
fly scale count 0 -g app -a logister-org
```

4. Take a final Prisma dump.
5. Restore the final dump into `logister_production`.
6. Set Fly secrets on `logister-org`.

Use the Fly private network hostname for runtime:

```bash
fly secrets set \
  DATABASE_URL="postgres://logister_app:PASS@shared-pg-iad.flycast:5432/logister_production?sslmode=disable" \
  DATABASE_MIGRATION_URL="postgres://logister_app:PASS@shared-pg-iad.flycast:5432/logister_production?sslmode=disable" \
  -a logister-org
```

Important: Logister `bin/release` prefers `DATABASE_MIGRATION_URL` over `DATABASE_URL`. Make sure `DATABASE_MIGRATION_URL` does not still point at Prisma.

7. Deploy or restart the app so the release command and runtime use the new database.
8. Start the app and worker:

```bash
fly scale count 1 -g app -a logister-org
fly scale count 1 -g worker -a logister-org
```

9. Verify `/up`, sign-in, ingest, Sidekiq, and production logs.

## Rollback

If cutover fails before writes resume:

1. Set `DATABASE_URL` and `DATABASE_MIGRATION_URL` back to Prisma values.
2. Restart Logister app and worker.
3. Keep the Fly restore for investigation.

If writes have already resumed on Fly, do not blindly roll back to Prisma. First decide whether to migrate Fly writes back to Prisma or accept data loss from the cutover window.

## Operations

Minimum operating checklist:

- Keep each app's runtime DB role limited to its own database.
- Keep total app connection pools under control. For this 2 GB shared VM, target fewer than 40 to 50 active database connections across all apps.
- Store generated DB passwords in a password manager and in each app's Fly secrets or equivalent secret store.
- Schedule daily logical dumps for each database and store them outside the Postgres VM.
- Keep Fly volume snapshots enabled, but do not rely on them as the only backup.
- Test restoring at least one logical dump before considering the migration complete.
- Monitor disk usage and alert at 70 percent and 80 percent.
- Watch Postgres memory, CPU, connection count, slow queries, and autovacuum health.

## Implementation Notes

Status as of 2026-06-13:

- Created Fly Postgres app `shared-pg-iad` in `iad`.
- Provisioned one `shared-cpu-2x` machine with `2048 MB` memory.
- Created encrypted `20 GB` Fly volume `pg_data`.
- Created runtime roles and databases for Logister, TQ, africa-unfiltered, and Follow Trades.
- Saved generated runtime database URLs locally in `tmp/fly-postgres-credentials.env`. This file is ignored by git and has mode `600`.
- Took a compressed Logister rehearsal dump from the current Prisma-backed production database: `tmp/logister-prisma-rehearsal-20260613.dump`.
- Restored the rehearsal dump into `logister_production` on `shared-pg-iad`.
- Filtered the Prisma-only `prisma_postgres` extension during restore. The restored Fly database has `pg_trgm` and `pgcrypto`.
- Verified Rails migration status from the deployed Logister image against the restored Fly database.
- Restarted the Postgres machine after the heavy restore and confirmed all Fly health checks returned to passing.

Verification results:

| Check | Result |
| --- | --- |
| Target extensions | `pg_trgm`, `pgcrypto` |
| Target database size after restore | About `3172 MB` |
| Latest target schema migration | `20260601223000` |
| Rails `db:migrate:status` from deployed image | Latest migrations are `up` |
| Fly health checks after restart | `pg`, `role`, and `vm` passing |

The rehearsal target is expected to be slightly behind the live Prisma source because production was still accepting writes while the dump and verification ran. During final cutover, stop app and worker writes before taking the final dump.

## Production Cutover

Status as of 2026-06-13 18:50 UTC:

- Intentionally skipped a final Prisma dump and reused the restored rehearsal database, accepting data loss for writes after `tmp/logister-prisma-rehearsal-20260613.dump` was taken.
- Stopped the existing Logister app and worker machines before swapping database secrets.
- Set `DATABASE_URL` and `DATABASE_MIGRATION_URL` on `logister-org` to the `logister_app` URL for `shared-pg-iad.flycast:5432/logister_production`.
- Brought Logister back with release `v310`.
- Confirmed the running web container parses `DATABASE_URL` as `shared-pg-iad.flycast|5432|logister_production`.
- Confirmed Rails connects as `logister_app` to `logister_production`.
- Confirmed `/up` returns `200`.
- Confirmed the Sidekiq worker is processing jobs.
- Confirmed Fly Postgres `pg`, `role`, and `vm` health checks are passing.

Post-cutover Rails verification:

| Check | Result |
| --- | --- |
| Database and user | `logister_production|logister_app` |
| `Project.count` | `10` |
| `User.count` | `2` |
| `IngestEvent.maximum(:id)` | `3124326` |

Logs still show ClickHouse ingest errors for `transaction` enum values. That appears unrelated to the Postgres host cutover and was visible around the same ingest flow.

## Completion Checklist

- [x] `shared-pg-iad` Postgres app exists in `iad`.
- [x] Postgres VM is `shared-cpu-2x` with `2048 MB` memory.
- [x] Postgres volume is `20 GB`.
- [x] Four app databases exist.
- [x] Four app runtime roles exist.
- [x] Logister rehearsal restore completed.
- [x] Logister verification passed.
- [x] Logister final Prisma dump intentionally skipped; cutover reused rehearsal restore.
- [x] Logister production restore available on Fly Postgres.
- [x] Logister Fly secrets point to Fly Postgres.
- [x] `DATABASE_MIGRATION_URL` no longer points to Prisma.
- [x] Logister app and worker restarted.
- [x] Post-cutover verification passed.
- [ ] Logical backups are scheduled and tested.
