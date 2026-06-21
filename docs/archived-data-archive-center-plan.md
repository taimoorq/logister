# Archived Data Archive Center Plan

Logister already records project-level retention policy state and archive run history. The next product step is to turn that operational data into a user-facing Archive Center that proves old telemetry is being protected and gives operators the actions they need when investigating an older event.

## Product Goal

The Archive Center should answer two questions quickly:

1. Is my archival plan working before old data is deleted?
2. Can I find old evidence when I need it for an incident, customer report, audit, or engineering review?

## First Placement

Start inside **Project settings -> Data** because the retention policy already lives there. Treat the first version as an operational evidence panel next to the existing retention settings.

If archive search becomes a frequent workflow, promote this into a first-class project navigation item later.

The implemented first structure is:

```text
Project Settings -> Data
  Retention Policy
  Archive Center
    Overview
    Coverage
    Catalog
    Search Archives
```

The Archive Center paths are URL-addressable through `archive_path=overview|coverage|catalog|search_archives`.

## Section Shape

### Archive Health

Show an at-a-glance status using existing policy and archive records:

- Archive retained data: enabled or disabled. This writes gzip JSONL exports to the configured archive service.
- Require archive before deletion: enabled or disabled. This is nested under Archive retained data and prevents matching rows from being removed unless their archive export succeeds.
- Last retention cleanup.
- Last successful archive.
- Last failed archive.
- Next expected retention sweep.
- Overall status: Not archiving, Archiving enabled with deletion not protected, Protected before deletion, Needs attention, or Archive gap detected.

In the UI, this belongs on the **Overview** path with a small set of routing actions:

- Review coverage.
- View catalog.
- Search archives.
- Edit retention policy.

### Coverage By Data Type

Show one row for each retention scope:

- Activity events: logs, metrics, transactions, and check-ins.
- Trace spans.
- Error events, only when closed-error retention is configured.
- Closed error groups.

Each row should show:

- Retention window.
- Hot data cutoff.
- Archived-through date.
- Last archived row count.
- Last deleted or pruned row count.
- Archive gap state.
- Latest status.

This belongs on the **Coverage** path. Each scope links into the catalog filtered to the related archive run scope.

### Archive Catalog

Replace the small recent-runs table with a searchable and paginated catalog:

- Scope.
- Archived time range.
- Exported at.
- Rows.
- Size.
- Object count.
- Status.
- Error message.
- Storage object keys in a details drawer.

This belongs on the **Catalog** path. The first implementation supports scope/status filters and object-key copy actions.

### Search Archives

Add an investigation form with filters an operator naturally has during incident review:

- Time range.
- Event UUID or numeric ID.
- Event type.
- Trace ID.
- Request ID.
- Session ID or user ID.
- Environment.
- Release.
- Service or route.
- Message contains.
- Error fingerprint or group.
- Check-in slug.

The first version can search archive metadata and object ranges. A later version can scan compressed JSONL archive objects in the background.

This belongs on the **Search Archives** path. The first implementation searches hot ingest events, hot trace spans, and candidate archive runs. Background archive-object scanning is still part of the later search phase.

### Actions

Add actions that help verify and investigate archive data:

- Download archive object.
- Copy object key.
- Retry failed archive run.
- Run retention dry run now.
- Run archive verification.
- Export selected archive range.
- Open matching hot data if it still exists.
- Rehydrate selected archived rows into a read-only investigation view.
- Create an incident bundle with matching rows plus summary JSON.

## Implementation Phases

### Phase 1: Confidence UI

Extend the Data settings page with archive health, coverage rows, gap detection, and fuller archive history using existing `project_retention_policies` and `telemetry_archives` records.

This phase should not require new archive storage behavior. It should make the existing retention runner evidence understandable.

### Phase 2: Archive Actions

Add a project-scoped archive controller with actions for listing, showing, downloading, retrying, and dry-running retention or archive work.

Use signed URLs where the storage service supports them. Fall back to Rails-mediated downloads when needed.

### Phase 3: Better Metadata

Store object-level metadata in a queryable form:

- Object key.
- Rows.
- Bytes.
- Checksum.
- Minimum and maximum timestamps.
- Event type counts.
- Environments.
- Releases.
- Services.

This lets archive search narrow candidate objects before opening gzip files.

### Phase 4: Archived Data Search

Add a background search job that scans candidate JSONL.gz archive objects and records matching rows into a temporary investigation result.

Search should be project-scoped, permission-checked, cancellable, and explicit about whether results came from hot data or archive objects.

### Phase 5: Read-only Rehydration

Do not restore archived rows into hot telemetry by default. Put matching rows into a read-only investigation view so old data does not pollute dashboards, monitors, metrics, or retention counts.

Only add true restore-to-hot-data behavior if there is a clear administrative need and an audit trail.

## Current Code Foundations

- `ProjectRetentionPolicy` stores retention windows, archive toggles, and last run results.
- `TelemetryArchive` stores project archive run history, object keys, row counts, byte counts, status, and failures.
- `Logister::ProjectRetentionRunner` performs project-scoped archive and prune work and records run results.
- `Logister::TelemetryArchiveExporter` writes gzip JSONL archive objects through Active Storage.

## Phase 1 Acceptance Criteria

- Users can see whether retained data archiving is active and whether deletion is protected by a successful archive.
- Users can see the last cleanup, last successful archive, last failed archive, and expected sweep cadence.
- Users can see retention coverage per data type.
- Users can see whether a scope has an archive gap.
- Users can see recent archive object metadata without opening logs or running Rails tasks.
- The UI handles projects with no archive runs yet, disabled archiving, failed archives, and forever-retained closed error groups.
