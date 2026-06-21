# SDK Parity And Self-Monitoring

This note tracks the event-reporting surface that Logister clients should keep aligned across runtimes, plus the Logister app paths that should report their own operational issues through `logister-ruby`.

## Client Reporting Parity

Each maintained client should support these event types:

- error
- log/message
- metric
- transaction
- span
- check-in
- custom ingest event

Each error/log/metric/transaction/span capture path should support:

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

Each span capture path should support:

- span name
- duration
- span ID
- parent span ID
- kind such as `server`, `browser`, `db`, `render`, `http`, or `resource`
- status
- started-at and ended-at timestamps
- trace ID and request ID

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

Current client coverage after the 2026-06-18 source-context pass:

| Client | Release | Notes |
| --- | --- | --- |
| Ruby | `logister-ruby` v0.2.8 | Supports errors, logs, metrics, transactions, spans, check-ins, source context, and `Logister.record_deployment`. |
| .NET | `Logister` / `Logister.AspNetCore` v0.1.5 | Supports errors, logs, metrics, transactions, spans, check-ins, source context, and `RecordDeploymentAsync`. |
| Python | `logister-python` v0.2.4 | Supports errors, logs, metrics, transactions, spans, check-ins, source context, GitHub Actions env fallback, and `record_deployment`. |
| JavaScript | `logister-js` v0.2.5 | Supports errors, logs, metrics, transactions, spans, check-ins, source context, browser context defaults, and `recordDeployment`. |
| Android | `logister-android` v0.1.2 | Kotlin-first Android SDK with Java interop; supports manual errors, logs, metrics, transactions, spans, check-ins, and source context. |
| iOS | `logister-ios` v0.1.3 | Swift Package Manager SDK; supports manual errors, logs, metrics, transactions, spans, check-ins, and source context. |

## Logister Self-Monitoring

Logister should report internal operational failures through `logister-ruby` so self-hosters can see app health in the same project they use for other services.

Currently instrumented:

- API client submission failures: unauthorized, missing/invalid envelopes, and validation errors are reported as sanitized Logister log events with payload shape and API key/project diagnostics.
- ClickHouse ingest failures: `ClickhouseIngestJob` reports both an error log and a count metric when optional analytics writes fail, throttled by failure signature so one outage cannot create an internal event storm.
- ClickHouse span ingest failures: `ClickhouseSpanIngestJob` reports both an error log and a count metric when optional span analytics writes fail, using the same signature throttle.
- Error digest scheduler health: `ProjectErrorDigestSchedulerJob` reports hourly check-ins with queued digest counts, reports error check-ins on scheduler failures, and reports schedule-enqueue failures as logs.

Good candidates for future additions:

- Redis cache error handler: report sampled cache backend failures, with a strict fingerprint to prevent noise.
- ClickHouse health checks: report state transitions only, not every failed probe.
- Mail delivery provider failures: rely on job error reporting for hard failures, then add focused logs if provider-level soft failures become common.
- Release lifecycle events: report deploy/check-in events from release automation once the deploy path is ready to own that contract.
