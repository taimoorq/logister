# Errors-only self-reporting

The Logister Rails application sends only error events through its own SDK. The same policy runs at boot and when installation settings refresh. SQL metrics and breadcrumbs, request spans and transactions, ordinary logs, scheduler check-ins, and deployment records are disabled for this application. Existing capture flags are ignored. Customer ingestion and release-update checks keep their existing behavior.

Handled ClickHouse and recurring-scheduler failures are error events. ClickHouse grouping/throttling and internal-origin markers remain in place. Unhandled Active Job failures use the SDK callback once. Reporting suppression still prevents failure feedback loops. Local Rails/Sidekiq logs and local pipeline summaries remain available for operations.

## Release transition

Before releasing, resolve the destination from the effective API credential/endpoint and the installation's configured self-monitoring project; do not infer a project from its display name or a historical numeric ID. Inventory only that project's check-in monitors. Record their UUIDs and current states, then pause obsolete self-check-in monitors using their existing pause operation. Leave scheduling, customer monitors, and error notifications active. Preserve previously paused reader monitors.

Record the cutover time and image identity for every web and worker process. Verify effective capture flags are false after boot and settings refresh. After old buffers drain, verify no new non-error self-events arrive; retained historical events and accepted delivery records are expected. Send one controlled error with `bin/rails logister:sample_telemetry` and verify grouping and source context. Check a handled failure, customer metric ingestion, delivery backlog/age, and local logs for recursive failures.

No telemetry or delivery rows need deletion. If error delivery regresses, repair forward or revert this coherent policy/producer change, retaining errors-only source settings where possible. Do not automatically unpause monitors or restore noisy capture during rollback. Version and release-impact metadata must be prepared against the then-current release line before deployment.
