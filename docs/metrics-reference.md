# Metrics Reference

Logister collects telemetry as raw events and spans, then derives chartable metrics for the dashboard and Insights views. PostgreSQL is the system of record. When ClickHouse is enabled, the same event and span data is mirrored into analytics tables for higher-volume reads.

## Collected Telemetry

| Family | Ingest shape | Important fields | Useful for |
| --- | --- | --- | --- |
| Errors | `event_type: "error"` through `POST /api/v1/ingest_events` | `message`, `level`, `fingerprint`, exception context, `environment`, `release`, `trace_id`, `request_id`, `session_id`, `user_id` | Grouping crashes and exceptions, assigning ownership, tracking release health, and jumping from an error to related logs or performance data. |
| Logs | `event_type: "log"` through `POST /api/v1/ingest_events` | `message`, `level`, `fingerprint`, context attributes, `environment`, `release`, trace/request/session/user identifiers | Reviewing operational breadcrumbs, warning trends, deploy notes, and context around nearby errors. |
| Metrics | `event_type: "metric"` through `POST /api/v1/ingest_events` | `message` as the metric name, optional `context.value`, optional `context.unit`, optional `duration_ms` or `durationMs` | Tracking app-specific counters and gauges such as queue depth, job count, cache hit rate, or external API timing. The reserved `db.query` metric powers database timing charts. |
| Transactions | `event_type: "transaction"` through `POST /api/v1/ingest_events` | `transaction_name` or `transactionName`, `duration_ms` or `durationMs`, `status`, route/request context, optional timing breakdowns | Measuring request, task, and job latency; finding slow endpoints; estimating SLO impact; and comparing performance by environment or release. |
| Spans | `event_type: "span"` through `POST /api/v1/ingest_events` | `trace_id`, `span_id`, `parent_span_id`, `name`, `kind`, `status`, `duration_ms`, `started_at`, `ended_at`, `environment`, `release`, `service`, `route`, `request_id`, tags | Building request waterfalls and performance breakdowns. Root `server` and `browser` spans represent top-level requests or page loads; child spans explain where the time went. |
| Check-ins | `event_type: "check_in"` through `POST /api/v1/ingest_events` or `POST /api/v1/check_ins` | `check_in_slug`, `check_in_status`, `expected_interval_seconds`, optional `duration_ms`, `environment`, `release`, `trace_id`, `request_id` | Watching scheduled jobs, workers, cron tasks, and heartbeat-style monitors. Logister derives `ok`, `error`, and `missed` monitor states from these events. |

Common normalized context fields include `environment`, `release`, `trace_id`, `request_id`, `session_id`, `user_id`, `transaction_name`, and `duration_ms`. CamelCase aliases such as `traceId`, `requestId`, `transactionName`, and `durationMs` are accepted and normalized where the app reads them.

## App And Add-on Support

The main app stores and displays the telemetry. The language add-ons are sender libraries that make it easier for apps in those runtimes to report the same shapes consistently. CFML uses direct HTTP payloads instead of a separate package.

| Feature | Main app | Ruby add-on | .NET add-on | Python add-on | JavaScript add-on | CFML / HTTP |
| --- | --- | --- | --- | --- | --- | --- |
| Error events | Receives, groups, assigns, and displays occurrences | Automatic Rails errors and manual errors | ASP.NET Core middleware and manual exceptions | FastAPI, Django, Flask, Celery, logging exceptions, and manual exceptions | Express middleware, console errors, and manual exceptions | Direct `error` payloads |
| Log events | Receives and shows activity/detail views | `Logister.report_log` | `CaptureMessageAsync` | Python `logging` integration and manual messages | `instrumentConsole()` and manual messages | Direct `log` payloads |
| Custom metric counts | Receives `metric` events and charts `metric:<name>` counts | Numeric/custom metric reporting | `CaptureMetricAsync` | `capture_metric` | `captureMetric` | Direct `metric` payloads |
| Custom metric values | Charts `metric_value:<name>` when `context.value` is numeric | Sends value/unit context | Sends value/unit context | Sends value/unit context | Sends value/unit context | Direct `context.value` and `context.unit` |
| Database query timing | Charts reserved `db.query` count, average, and P95 duration | ActiveRecord DB metric instrumentation | Direct metric support for DB timing | Direct metric support for DB timing | Direct metric support for DB timing | Direct `db.query` metric payloads |
| Transactions | Receives transaction counts, average duration, and P95 duration | Rails/request and manual transactions | ASP.NET Core request and manual transactions | Framework request/task and manual transactions | Express/request, browser, job, and manual transactions | Direct `transaction` payloads |
| Spans | Receives spans and builds request load breakdowns | Manual spans and opt-in Rails request spans | Manual spans and opt-in ASP.NET Core request spans | Manual spans and opt-in FastAPI/Django/Flask request spans | Manual spans, Express request spans, and browser page/resource spans | Direct root and child `span` payloads |
| Check-ins | Receives events, tracks monitor state, and derives missed status | Cron, scheduler, and worker check-ins | Worker and scheduled-task check-ins | Celery and manual check-ins | Job/script check-ins | Direct check-in endpoint or payloads |
| Environment and release | Filters, cataloging, release health, and event detail | Supported on capture paths | Supported on capture paths | Supported on capture paths | Supported on capture paths | Direct fields or context |
| Trace/request correlation | Related logs, event detail, transaction/spans, and ClickHouse fields | Trace ID and request ID options | Trace ID and request ID options | Trace ID and request ID options | Trace ID and request ID options | Direct fields or context |
| Session/user context | Event detail, related context, and attribute visibility | Session ID and user ID options | Session ID and user ID options | Session ID and user ID options | Session ID and user ID options | Direct fields or context |
| Custom dimensions | Insights attribute filters for safe scalar context | Custom context and tags | Custom context and tags | Custom context and tags | Custom context and tags | Direct context and tags |

## Developer Reporting Guide

Use this section when you are building or reviewing an integration and want to know what Logister can collect, display, filter, or report on.

### Event Envelope Fields

| Field | Applies to | Accepted aliases | How Logister uses it |
| --- | --- | --- | --- |
| `event_type` | All event payloads | `eventType` | Chooses the storage and UI path. Accepted values are `error`, `log`, `metric`, `transaction`, `span`, and `check_in`. |
| `message` | Errors, logs, metrics, transactions, check-ins | `name` for spans | Primary label in the inbox, activity feed, event detail, and metric catalog. For custom metrics, this is the metric name. |
| `level` | Errors, logs, metrics, transactions | None | Severity such as `info`, `warn`, `error`, or `fatal`; used for display and error severity. |
| `fingerprint` | Errors and repeated operational signals | None | Groups repeated errors or recurring logs/metrics into stable buckets. |
| `occurred_at` | All non-span events | `occurredAt` | Event time. If omitted, Logister uses receive time. |
| `context` | All event payloads | None | Structured metadata used by detail views, related-log matching, filters, release health, performance, monitors, and custom dimensions. |

### Context Fields Logister Reads

| Context field | Accepted aliases | Powers |
| --- | --- | --- |
| `environment` | Top-level `environment` | Environment filters, event detail, ClickHouse dimensions, and monitor separation. |
| `release` | Top-level `release` | Release filters, release health, event detail, and ClickHouse dimensions. |
| `service` | Top-level or context | Service attribution in ClickHouse and custom filtering when sent as scalar context. |
| `trace_id` | `traceId`, nested `trace.traceId` | Related logs, event correlation, spans, and ClickHouse dimensions. |
| `request_id` | `requestId`, nested `trace.requestId` | Related logs, event correlation, request detail, spans, and ClickHouse dimensions. |
| `session_id` | `sessionId` | Related context and event detail. |
| `user_id` | `userId`, nested `user.id` | User-scoped investigation context. |
| `transaction_name` | `transactionName` | Transaction labels, performance views, event detail, and ClickHouse dimensions. |
| `duration_ms` | `durationMs` | Transaction duration, `db.query` duration, event detail, and optional check-in runtime. |
| `value` | None | Custom metric average series through `metric_value:<name>` when numeric. |
| `unit` | None | Human-readable unit for custom metric values. |
| `tags` | None | Stored as tag maps for ClickHouse and event context when integrations send them. |
| `exception` / `exception_class` | Runtime-specific exception context | Error detail and ClickHouse exception dimensions. |
| `request` | Runtime-specific request context | Error detail panes, request method/URL/path highlights, and investigation context. |
| `check_in_slug` | `monitor_slug`, check-in endpoint `slug` | Monitor identity. |
| `check_in_status` | `status` | Monitor state; `error` marks the latest run failed, other values default to healthy unless missed by interval. |
| `expected_interval_seconds` | Check-in endpoint field | Monitor missed-check-in detection. |

### Span Fields

| Field | Accepted aliases | Required? | How Logister uses it |
| --- | --- | --- | --- |
| `trace_id` | `traceId`, context `trace_id`, context `trace.traceId` | Yes | Groups root and child spans into one trace. |
| `span_id` | `spanId`, context `span_id` | Yes | Unique span identifier within a project and trace. |
| `parent_span_id` | `parentSpanId`, context `parent_span_id` | No | Links child spans to a root or parent span. Root spans leave it blank. |
| `name` | `message`, context `name`, context `span_name` | Yes | Span label in performance views. |
| `kind` | `span_kind`, `spanKind` | No | Normalized to one of `app`, `browser`, `cache`, `db`, `http`, `internal`, `queue`, `render`, `resource`, or `server`; unknown kinds become `internal`. |
| `status` | context `status` | No | Status text for the span. |
| `duration_ms` | `durationMs` | Yes | Span duration used for waterfall and request load breakdowns. |
| `started_at` | `startedAt`, `occurred_at` | Yes | Span start time. |
| `ended_at` | `endedAt` | No | End time; if absent, Logister derives it from `started_at` and `duration_ms`. |

### What Each UI Can Report On

| View | Data it uses | Best fields to send |
| --- | --- | --- |
| Inbox | Error events and grouped error occurrences. | `event_type`, `message`, `level`, `fingerprint`, exception context, `environment`, `release`, request context. |
| Event detail | Raw event context, runtime presenters, occurrences, and related logs. | Request method/path/URL, stack trace or exception data, trace/request/session/user IDs, safe custom context. |
| Activity | Logs, metrics, transactions, and check-ins. | Clear `message`, `level`, `environment`, `release`, and app-specific context. |
| Performance | Transactions, `db.query` metrics, trace spans, and release context. | `transaction_name`, `duration_ms`, `status`, route, `db.query` duration metrics, span trace fields. |
| Monitors | Check-in events and monitor records. | `check_in_slug`, `check_in_status`, `expected_interval_seconds`, `environment`, `release`, optional runtime. |
| Insights | Event counts, transaction durations, `db.query` metrics, custom metric values, environment/release filters, and safe scalar attributes. | Stable metric names, numeric `context.value`, `context.unit`, low-cardinality context attributes. |
| ClickHouse | Mirrored raw events/spans and one-minute rollups when enabled. | `service`, `environment`, `release`, `transaction_name`, tags, span route, trace/request IDs. |

### Data Collection Boundaries

Logister can store whatever structured context an integration sends, so integrations should be deliberate about what they collect. Prefer safe, investigation-friendly metadata:

- Good context: route names, HTTP method, status code, deploy release, environment, service, job name, queue name, tenant tier, region, feature flag, sanitized request identifiers, trace/request/session/user IDs, and runtime timings.
- Be careful with: raw SQL, full URLs with user data, request parameters, response bodies, headers, local variables, and frame locals. Only send them when the operator has reviewed privacy and retention expectations.
- Avoid: passwords, tokens, API keys, authorization headers, cookies, payment data, medical data, raw email bodies, and any data your team would not want stored in an observability database.

## Insights Metrics

These are the built-in chart series available in project Insights.

| Metric key | Unit | What it means | Useful for |
| --- | --- | --- | --- |
| `events.total` | count | Count of every event in the selected project scope: errors, logs, metrics, transactions, and check-ins. | Overall ingestion volume, deploy comparisons, and spotting telemetry drops or spikes. |
| `errors.count` | count | Count of `error` events. | Incident detection, release regressions, and triage workload. |
| `activity.count` | count | Count of all non-error events. | Understanding supporting telemetry volume without error noise. |
| `logs.count` | count | Count of `log` events. | Warning/debug volume and service activity changes. |
| `check_ins.count` | count | Count of `check_in` events. | Scheduler and worker heartbeat volume. |
| `transactions.count` | count | Count of `transaction` events. | Request/job throughput for instrumented paths. |
| `transactions.avg` | ms | Average `duration_ms` or `durationMs` for transaction events with numeric durations. | Baseline latency trend and broad performance regressions. |
| `transactions.p95` | ms | 95th percentile `duration_ms` or `durationMs` for transaction events with numeric durations. | Tail latency, user-impacting slow paths, and SLO-style review. |
| `db.query.count` | count | Count of metric events where `message` is exactly `db.query`. | Database query volume and suspected N+1 or high-chatter pages. |
| `db.query.avg` | ms | Average duration for numeric `duration_ms` or `durationMs` on `db.query` metric events. | Database latency trend and query-plan changes. |
| `db.query.p95` | ms | 95th percentile duration for numeric `duration_ms` or `durationMs` on `db.query` metric events. | Tail database latency and occasional heavy query detection. |

Insights supports `1h`, `6h`, `24h`, and `7d` windows. Bucket size is minute for `1h`, hourly for `6h` and `24h`, and daily for `7d`.

## Custom Metric Series

Custom metric events are regular `event_type: "metric"` events whose `message` is not `db.query`.

| Series key | Unit | What it means | Useful for |
| --- | --- | --- | --- |
| `metric:<name>` | count | Count of metric events with `message` equal to `<name>`. | Counters such as jobs processed, cache misses, webhooks received, or retries. |
| `metric_value:<name>` | value | Average numeric `context.value` for metric events with `message` equal to `<name>`. | Gauges and measurements such as queue depth, payload size, memory usage, or external API latency. |

Custom metric discovery samples recent metric events in the selected window, shows the most common names, and only adds the `metric_value:<name>` series when `context.value` is numeric. Keep metric names stable and put units in `context.unit` so charts and event detail remain understandable.

## Performance Breakdown

The Performance page prefers trace spans when root `server` or `browser` spans are present. If no root spans are available, it falls back to transaction events.

| Segment | Span kinds or transaction fields | Useful for |
| --- | --- | --- |
| App | Root duration after known child time is subtracted; `browser` spans are treated as app time. | Controller, application, or client-side work that is not explained by a child segment. |
| Database | Child span kind `db`, plus transaction timing keys such as `dbRuntimeMs` or `db_runtime_ms`; aliases `database` and `sql` map here. | Query load, slow SQL, N+1 behavior, and database saturation. |
| Render | Child span kind `render`, plus transaction timing keys such as `viewRuntimeMs` or `view_runtime_ms`; aliases `view` and `template` map here. | Template/view rendering cost. |
| HTTP | Child span kind `http`, transaction dependency durations from `dependencyCalls` or `dependencies`; aliases `external` and `client` map here. | Downstream services, third-party APIs, and network-bound work. |
| Cache | Child span kind `cache`. | Cache latency and cache backend pressure. |
| Queue | Child span kind `queue`. | Background job enqueue/dequeue and broker timing. |
| Resources | Child span kind `resource`. | Browser resource loads or other resource-level work. |
| Other | Any unrecognized timing breakdown key or remaining measured duration. | Time that needs better instrumentation or does not fit another segment. |

Transactions may also send `timing_breakdown` or `timings` as a hash of segment names to milliseconds. Logister normalizes common aliases, then keeps any unknown keys in `Other`.

## Filter Dimensions

Insights can filter by environment, release, and selected custom scalar context attributes. Attribute filters intentionally ignore reserved operational fields such as `duration_ms`, `trace_id`, `request_id`, `transaction_name`, `check_in_slug`, exception payloads, stack traces, request/response bodies, and SQL/query text.

Good custom attributes are short, stable, low-cardinality values such as `tenant_id`, `plan`, `region`, `service`, `feature`, or `queue`. Avoid high-cardinality or sensitive values such as raw email addresses, full URLs with user data, tokens, and request bodies.
