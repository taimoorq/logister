# SDK Parity And Self-Monitoring

This note tracks the event-reporting surface that Logister clients should keep aligned across runtimes, plus the Logister app paths that should report their own operational issues through `logister-ruby`.

## Client Reporting Parity

Each maintained client should support these event types:

- error
- log/message
- metric
- transaction
- check-in
- custom ingest event

Each error/log/metric/transaction capture path should support:

- level
- message override where applicable
- fingerprint
- occurred-at timestamp
- context
- environment
- release
- trace ID
- request ID
- session ID
- user ID

Each metric capture path should support:

- metric name
- numeric value
- optional unit
- structured `metric` context with `name`, `value`, and `unit`
- compatibility `value` and `unit` context fields

Each check-in capture path should support:

- slug
- status
- environment
- release
- duration
- checked-at or occurred-at timestamp
- expected interval
- trace ID
- request ID
- context

Current client coverage after the 2026-05-21 parity pass:

| Client | Release | Notes |
| --- | --- | --- |
| Ruby | `logister-ruby` v0.2.6 | Manual errors share Rails enrichment; metrics accept value/unit; check-ins accept environment, release, occurred-at, trace ID, and request ID options. |
| .NET | `Logister` / `Logister.AspNetCore` v0.1.3 | Check-ins now include top-level release plus interval, trace ID, and request ID coverage. |
| Python | `logister-python` v0.2.1 | Metrics now accept unit, level, and fingerprint while preserving structured metric context. |
| JavaScript | `logister-js` v0.2.3 | Capture calls accept per-event routing fields; metrics include structured metric context; check-ins include release, interval, trace ID, and request ID. |

## Logister Self-Monitoring

Logister should report internal operational failures through `logister-ruby` so self-hosters can see app health in the same project they use for other services.

Currently instrumented:

- API client submission failures: unauthorized, missing/invalid envelopes, and validation errors are reported as sanitized Logister log events with payload shape and API key/project diagnostics.
- ClickHouse ingest failures: `ClickhouseIngestJob` reports both an error log and a count metric when optional analytics writes fail.
- Error digest scheduler health: `ProjectErrorDigestSchedulerJob` reports hourly check-ins with queued digest counts, reports error check-ins on scheduler failures, and reports schedule-enqueue failures as logs.

Good candidates for future additions:

- Redis cache error handler: report sampled cache backend failures, with a strict fingerprint to prevent noise.
- ClickHouse health checks: report state transitions only, not every failed probe.
- Mail delivery provider failures: rely on job error reporting for hard failures, then add focused logs if provider-level soft failures become common.
- Release lifecycle events: report deploy/check-in events from release automation once the deploy path is ready to own that contract.
