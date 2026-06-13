# PostgreSQL Ingest Events Partitioning Plan

Logister stores hot event detail in PostgreSQL `ingest_events`. The table is already indexed around project-scoped time-series reads, but continued growth will make retention, index bloat, and dashboard scans more expensive. The target design is one logical `ingest_events` table backed by PostgreSQL declarative partitions.

## Target Shape

- Keep the Rails model and logical table name as `IngestEvent` / `ingest_events`.
- Partition `ingest_events` by `occurred_at`, starting with monthly range partitions.
- Preserve existing event `id` values during cutover.
- Use local partition indexes matching the current high-volume query paths.
- Add composite reference keys where other tables point at events, because PostgreSQL partitioned unique constraints must include the partition key.

## Why Not One Table Per Project

Per-project tables make some single-project scans smaller, but they complicate migrations, retention, Rails associations, dashboard queries across multiple projects, and operational tooling. Native partitions provide the same pruning benefits while preserving one logical table.

## Phase 1: Prepare Existing References

Add nullable companion timestamps beside every event reference:

- `error_occurrences.ingest_event_occurred_at`
- `error_groups.latest_event_occurred_at`
- `check_in_monitors.last_event_occurred_at`

Backfill those columns from `ingest_events.occurred_at`. Update application writes so future rows populate both the event ID and its event timestamp. Keep the existing single-column foreign keys in place during this phase.

This phase is safe to deploy before partitioning because the new columns are additive and nullable.

## Phase 2: Switch Schema Dumping

Before introducing the partitioned table, switch Rails to SQL schema dumps:

```ruby
config.active_record.schema_format = :sql
```

Partition definitions, raw partition indexes, and future maintenance objects are represented more reliably in `structure.sql` than `schema.rb`.

## Phase 3: Create the Shadow Partitioned Table

Create `ingest_events_partitioned` with the same data columns as `ingest_events`, partitioned by `occurred_at`.

Use partition-compatible uniqueness:

```sql
UNIQUE (id, occurred_at)
```

For `uuid`, either use `UNIQUE (uuid, occurred_at)` or a non-unique index during the initial cutover. A globally unique `uuid` constraint on `uuid` alone is not valid on a table partitioned only by `occurred_at`.

Create monthly partitions plus a default partition:

```text
ingest_events_2026_01
ingest_events_2026_02
...
ingest_events_default
```

Recreate the current indexes from `ingest_events` on the partitioned parent, especially indexes for:

- `project_id, occurred_at`
- `project_id, event_type, occurred_at`
- activity cursor reads
- environment and release filters
- custom metric and DB query paths
- retention paths
- UUID lookup

## Phase 4: Backfill and Mirror

For small installs, copy rows during a maintenance window.

For larger installs:

1. Create a trigger on old `ingest_events` to mirror inserts, updates, and deletes into `ingest_events_partitioned`.
2. Run a dry-run backfill to estimate the remaining source rows.
3. Backfill historical rows in bounded batches. The backfill is idempotent and may be rerun.
4. Compare row counts by month.
5. Compare `MIN(id)`, `MAX(id)`, aggregate ID sums, and full-row field drift.
6. Pause writes briefly for the final delta sync.

The mirror trigger is installed by:

```sh
bin/rails db:migrate
```

Check the trigger, shadow row counts, partition tree, and current drift:

```sh
bin/rails logister:postgres:partitioning:status
```

Dry-run the catch-up copy:

```sh
bin/rails logister:postgres:partitioning:backfill
```

Backfill all historical events:

```sh
DRY_RUN=false CONFIRM=backfill BATCH_SIZE=5000 bin/rails logister:postgres:partitioning:backfill
```

Backfill a bounded time window if the table needs smaller rollout chunks:

```sh
DRY_RUN=false CONFIRM=backfill FROM=2026-01-01 TO=2026-02-01 bin/rails logister:postgres:partitioning:backfill
```

Validate before cutover:

```sh
bin/rails logister:postgres:partitioning:validate
```

Proceed to Phase 5 only when validation reports `valid: true`, `missing_in_shadow: 0`, `extra_in_shadow: 0`, and `mismatched_rows: 0`.

### Live-Sized Rehearsal Notes

The Fly rehearsal dump from `tmp/logister-prisma-rehearsal-20260613.dump` restored to development with:

- `3,124,313` `ingest_events`
- event range: `2026-02-15 07:41:50` through `2026-06-13 17:24:57`
- monthly distribution:
  - `2026-02`: `352`
  - `2026-03`: `3,962`
  - `2026-04`: `2,328`
  - `2026-05`: `2,389,332`
  - `2026-06`: `728,339`

Rehearsal timings on the local restored database:

- `bin/rails db:migrate`: `4s`
- pre-backfill `status`: `7s`
- dry-run backfill over all rows: `9s`
- confirmed backfill with `BATCH_SIZE=10000`: `171s`
- full validation: `25s`
- cutover preflight after backfill: `17s`
- cutover command: `18s`, with the locked transaction itself taking `0.044s`
- post-cutover copy validation: `16s`
- composite foreign key validation: `2s`

The backfill must page by source primary key `id`, not by `(occurred_at, id)`. On the restored database, ordering by `(occurred_at, id)` forced a multi-million-row sort per batch because the old table does not have a matching global index. Paging by `id` uses `ingest_events_pkey` and routes rows into the correct partition from each row's `occurred_at`.

Rails cannot infer a single-column primary key from the post-cutover partitioned table because PostgreSQL requires partitioned unique constraints to include the partition key. `IngestEvent` must explicitly declare `self.primary_key = :id`; the sequence still preserves logical ID uniqueness.

Storage from the same rehearsal:

- original `ingest_events`: `3.1 GB`
- partitioned shadow tree after backfill: `3.8 GB`
- database after backfill while both copies exist: `7.0 GB`

Before production backfill, confirm the Postgres volume has enough free space for the original table, the shadow table plus indexes, and WAL generated by the copy. For this snapshot, budget at least another `4 GB` for the shadow event table tree, plus operational headroom.

Avoid polling `status` or `validate` continuously; both intentionally scan/join millions of rows. Use them at checkpoints, and monitor raw copy progress with:

```sql
SELECT COUNT(*) FROM ingest_events_partitioned;
```

## Phase 5: Cut Over

During a short maintenance transaction:

1. Run preflight checks and require a clean shadow validation.
2. Enter the maintenance window.
3. Lock writes to `ingest_events`, `ingest_events_partitioned`, and the three referencing tables.
4. Drop the mirror trigger/function.
5. Drop inbound single-column foreign keys that reference `ingest_events(id)`.
6. Rename `ingest_events` to `ingest_events_unpartitioned_backup`.
7. Rename `ingest_events_partitioned` to `ingest_events`.
8. Attach/reset the existing sequence to `ingest_events.id`.
9. Add composite foreign keys as `NOT VALID`:

```sql
FOREIGN KEY (ingest_event_id, ingest_event_occurred_at)
REFERENCES ingest_events(id, occurred_at)
NOT VALID
```

Repeat for `error_groups.latest_event_id/latest_event_occurred_at` and `check_in_monitors.last_event_id/last_event_occurred_at`.

Use the cutover tasks rather than performing the SQL manually:

```sh
bin/rails logister:postgres:partitioning:cutover_preflight
CONFIRM=cutover LOCK_TIMEOUT=30s bin/rails logister:postgres:partitioning:cutover
bin/rails logister:postgres:partitioning:validate_cutover_copy
```

Restart web and worker processes immediately after the cutover command. The table rename changes the PostgreSQL relation behind `ingest_events`; long-lived Rails processes may have prepared statements or schema metadata cached for the old relation.

`cutover_preflight` checks:

- `ingest_events` exists and is still unpartitioned
- `ingest_events_partitioned` exists and is partitioned
- `ingest_events_unpartitioned_backup` does not already exist
- the mirror trigger is installed
- source/shadow validation is clean
- companion reference timestamps are populated where event IDs are present

After cutover, `validate_cutover_copy` compares the new partitioned `ingest_events` against `ingest_events_unpartitioned_backup`. Run it before resuming writes if possible. Once writes resume, the backup table is intentionally stale and should not be expected to match the live table.

The cutover rake task clears its own Active Record connection caches after the swap, but it cannot clear already-running web or worker process connection caches.

## Phase 6: Validate and Retire the Backup

After the cutover, validate constraints during a quiet period:

```sh
CONFIRM=validate_constraints bin/rails logister:postgres:partitioning:validate_cutover_constraints
```

Verify:

- event counts match before and after cutover
- no orphan `error_occurrences` rows
- no orphan `error_groups.latest_event_id` references
- no orphan `check_in_monitors.last_event_id` references
- API ingest still accepts events
- error grouping still creates occurrences
- project inbox/event detail still render
- retention still clears references before deleting events

Keep `ingest_events_unpartitioned_backup` for at least one retention window or until operational confidence is high, then drop it in a separate maintenance task.
