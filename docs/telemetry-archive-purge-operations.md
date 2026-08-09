# Telemetry archive and project purge operations

Logister records archive and deletion work in PostgreSQL before changing an
external store. Deploy the additive migrations before the application code. Do
not shorten retention or enable automatic ClickHouse project deletion until a
staging purge has reached a verified terminal state.

## Archive lifecycle

Manifest version 2 uses these states:

`pending → uploading → verifying → completed`

A failed upload or verification moves the manifest to `failed`. Every object
has a deterministic key beneath `manifests/project=<uuid>/archive=<id>`, exact
source IDs and timestamps, expected rows and bytes, an MD5 upload checksum, and
a SHA-256 verification checksum. New objects also record an immutable storage
generation locator and the object version returned by S3. Each manifest snapshots an immutable upper
source ID before enumeration, so a busy archive run is finite. Retention deletes only the exact references in
a completed manifest. Rows accepted after enumeration remain in PostgreSQL for
the next run.

Retention also checks the PostgreSQL delivery ledger by exact source identity.
An event or span remains in PostgreSQL while any delivery is `pending`,
`processing`, `retrying`, or `terminal_failed`, even when it is already present
in a verified archive. The manifest records the protected row count and source
cleanup retries on later retention runs after every delivery becomes
`completed`. Resolve or replay terminal failures before expecting replay-buffer
retention to advance.

Every cleanup attempt re-downloads and verifies the exact manifest objects
immediately before deleting source rows. It also reapplies the current
signal-specific cutoff and workflow predicates. Lengthening retention therefore
keeps a previously archived row, and a missing or corrupt object leaves
PostgreSQL untouched. Cleanup streams one manifest-object reference batch at a
time; run results retain counts and checksums rather than tenant-sized identity
arrays.

Manifests written before immutable storage locators fail closed during delayed
cleanup unless an operator has proved they remain in the current store and sets
`LOGISTER_ATTEST_LEGACY_ARCHIVE_STORAGE_CURRENT=true`.

The legacy `logister:telemetry:prune_hot` global deletion task is intentionally
disabled because it cannot honor per-project archive policy or delivery state.
Use `logister:telemetry:retention` in dry-run mode, review
`protected_by_delivery`, and then run the confirmed per-project retention path.

Inspect or repair a manifest from a Rails console:

```ruby
archive = TelemetryArchive.find(123)

Logister::TelemetryArchiveInspector.new(archive: archive).call
Logister::TelemetryArchiveRetry.new(archive: archive).call
Logister::TelemetryArchiveReplay.new(archive: archive, processor: ->(row, **) { puts row.dig("attributes", "id") }).call
Logister::TelemetryArchiveRestore.new(archive: archive, dry_run: true).call
```

Run restore without `dry_run` only after checking that the archived project's
API keys still exist. Restore preserves source IDs, skips existing identities,
and clears an error-group reference if the workflow group no longer exists.

Object stores do not expose one portable listing API through Active Storage.
Obtain an operator-reviewed inventory from the configured bucket or disk, then
pass only keys beneath the configured archive prefix:

```ruby
Logister::TelemetryArchiveOrphanCleanup.new(
  candidate_keys: approved_inventory,
  dry_run: true
).call
```

Review the dry-run result before setting `dry_run: false`. The cleanup service
will not delete keys recorded by either a legacy manifest or a version 2 object
manifest.

## Project purge lifecycle

Deleting a project first archives the project, revokes active credentials, and
sets `projects.purge_requested_at`. Projectors must refuse claims and writes for
a tombstoned project. The durable ledger then runs:

1. Archive and private symbol objects, with absence verification.
2. ClickHouse raw facts and rollups. An external gate stops here while the
   PostgreSQL project, ownership, and durable authorization context still exist.
3. PostgreSQL telemetry and the project control-plane row.
4. Redis-derived project namespaces, followed by a second absence pass.

The `project_purges` row survives deletion of the project and retains a
per-store attempt/result/error history. A purge becomes `completed` only after
all store steps are `completed` or `skipped` and the PostgreSQL project row is
absent.

Only one worker owns a purge ledger at a time. External writes are ordered on
the project tombstone, followed by a configurable quiescence interval. Archive
and ClickHouse steps each perform an initial deletion and then a delayed second
deletion/absence verification. S3 verification enumerates and removes all
versions and delete markers for every recorded key; a current-key `HEAD` is not
accepted as proof that noncurrent versions are gone.
The archive role therefore needs bucket-scoped `s3:ListBucketVersions` plus
object-scoped `s3:GetObject`, `s3:GetObjectVersion`, `s3:PutObject`,
`s3:DeleteObject`, and `s3:DeleteObjectVersion` for the configured prefix.
Object Lock, retention holds, or denied historical-version access leave the step
in `awaiting_external`; they must never be treated as successful deletion.
The one-minute recovery sweep reconstructs due quiescence/final-verification
jobs from PostgreSQL, so losing a scheduled Redis job cannot strand an automatic
purge phase.

Automatic ClickHouse mutation is an explicit rollout gate. With ClickHouse
configured, a purge stops in `awaiting_external` until this setting is enabled:

```bash
LOGISTER_ENABLE_PROJECT_PURGE_CLICKHOUSE=true
```

Disabled mode is never treated as evidence that ClickHouse was unused. Logister
records a non-secret locator for each ClickHouse store generation it observes.
Before changing clusters, register both the old and new configured stores:

```bash
CONFIRM=register bin/rails logister:clickhouse:generation:register
```

After independently inventorying every cluster ever used by the installation,
set `LOGISTER_ATTEST_CLICKHOUSE_GENERATION_INVENTORY_COMPLETE=true` and resume
the purge. If ClickHouse has provably never been used, the narrower
`LOGISTER_ATTEST_CLICKHOUSE_NEVER_USED=true` attestation permits the skipped
step only when the recorded generation list is empty. These attestations are
copied into the durable purge snapshot on request or resume.

Historical clusters are contacted independently of the current read/write
mode. If generations use different credentials, provide a secret JSON mapping
through `LOGISTER_PROJECT_PURGE_CLICKHOUSE_CREDENTIALS_JSON`, keyed by the
recorded generation ID. Passwords are never stored in the generation registry.
An unreachable or unregistered generation leaves the purge visibly in
`awaiting_external`.

Use `LOGISTER_PROJECT_PURGE_CLICKHOUSE_TABLES` for additional comma-separated
typed fact or rollup tables beyond the built-in raw and one-minute tables. Test
every additional table in staging; each must contain `project_id`. The adapter
also discovers every MergeTree-family table with a `project_id` column in each
recorded Logister database, so materialized aggregate state cannot survive raw
fact deletion unnoticed.

The default remote-write quiescence is 120 seconds and the final repeat pass is
30 seconds later. Override only with measured server/client timeout evidence via
`LOGISTER_PROJECT_PURGE_WRITE_QUIESCENCE_SECONDS` and
`LOGISTER_PROJECT_PURGE_FINAL_VERIFICATION_SECONDS`.

After changing the gate or repairing external access, an authorized project
owner, original requester, or application administrator can resume through the
retry endpoint or a Rails console:

```ruby
purge = ProjectPurge.find(456)
Logister::ProjectPurgeResume.new(project_purge: purge, actor: operator).call
```

Inspect `project_purges.audit_log` and the ordered `project_purge_steps` before
declaring deletion complete. Do not manually remove a ledger that is `failed`
or `awaiting_external`; it is the durable recovery handle. ClickHouse precedes
PostgreSQL specifically so an external wait retains the project's normal owner
visibility and authorization context.
