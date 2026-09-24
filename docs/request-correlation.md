# Request correlation

Logister 3.7 adds explicit relationships between projects and a bounded occurrence
lookup. The matching SDK releases add request context and opt-in outbound HTTP
instrumentation. Prepared versions are in `config/release-sets/v3.7.0.yml`;
`config/ecosystem-versions.json` continues to describe verified public releases.

## Wire contract

Application calls carry W3C version 00 `traceparent` and an optional bounded
`x-request-id`. Trace IDs are 32 lowercase hex characters, span IDs 16, neither
all zero. Receivers preserve trace flags, create a local server span, and set its
parent to the incoming span. Every outbound attempt has its own span. Existing
valid outbound instrumentation owns its header; native .NET Activity is reused.

SDK payload context uses `trace_id`, `span_id`, `parent_span_id`, and `request_id`.
Legacy camelCase and nested `trace` / `request` aliases remain readable. Canonical
snake_case wins for display. Distinct valid values for the same identifier are
marked as conflicts and excluded from correlation. Opaque historical IDs remain
searchable, but cannot be emitted as W3C headers. Identifier limits are 128 ASCII
characters (200 for request IDs); identifiers are neither authentication nor
proof that an untrusted caller actually executed an operation.

Backend scopes are thread/fiber-local (Ruby), AsyncLocalStorage (Node), ContextVar
(Python), and Activity/AsyncLocal (.NET). Mobile wrappers return immutable handles
for explicit attachment to handled errors. No global last-request value is used.
SDKs preserve event UUIDs and capture times across existing retry/offline queues.
Historical app exits and aggregate MetricKit diagnostics are not linked to a
request through time, users, sessions, or guessed activity.

Outbound propagation is opt-in and exact-origin allowlisted. Exclude telemetry
and mobile-token issuer URLs. URLSession, fetch, and HttpURLConnection wrappers
return redirects without following them. The optional Android OkHttp module
checks every hop with an application call scope and a network interceptor.
Generic Ruby/Python/.NET header helpers require the caller to disable redirects
or revalidate each hop. Browser CORS must allow traceparent and x-request-id.
No baggage or user identity propagation is introduced.

## Project relationships and reads

A manager of both projects creates a directed `calls` connection with explicit
source/target environment pairs. Either endpoint manager can remove it. Changes
are audited. A connection grants no access. Readers need current project access
and, for CLI tokens, an intersecting allowlist and all relevant scopes. Lookups
recheck access, lifecycle, opt-in state, links, and environment mappings before
returning. Archived or purging projects are excluded. Linking is one hop only.

In the backend project's **Settings → Integrations → Connected projects**, use
**Link an app to this backend**. Choose the mobile project from the **App project**
dropdown and select **Review connection**. The review names both projects and
shows the request direction. Choose the **App environment** and **Backend
environment**, then select **Link projects**. Repeat for Android and iOS.
Starting from a mobile project instead shows **Link this app to a backend**.

Project choices include the integration type and slug, exclude inactive or
unmanaged projects, and disable existing connections. Mobile projects cannot be
selected as receiving backends. Environment suggestions use up to 500 recent
PostgreSQL events and 500 spans per project plus 50 recent deployments. Common
names are identified separately; neither list chooses an environment for the
user. For absent or ClickHouse-only values, choose **Other environment** and enter
the exact name. Submitted direction, project and custom names survive validation
errors. Both steps work without JavaScript; Stimulus only reveals the custom field.

The related requests panel starts at one occurrence. It searches error, log,
transaction, and span records using a shared trace ID, or a request ID without a
contradictory trace. A matching parent span is stronger evidence. Endpoint names
and timing provide context, never establish the link themselves. Deployments
require an exact release and environment match in that record's own project,
with exactly one candidate preceding the occurrence. A mobile version is never
used to choose a backend deployment.

Default range is ±15 minutes, with a 24-hour maximum. Limits: ten neighbors,
500 rows per signal query, 500 returned rows, 1 MiB serialized payload. Only
bounded operation/identity metadata is returned, not messages, headers, bodies,
or arbitrary context. PostgreSQL statement timeout uses the existing bounded
CLI setting. ClickHouse reads use coverage-aware routing and deduplicated fact
views; PostgreSQL fallback retention gaps and truncation remain visible. IDs
are normalized at ingest and resolved for historical records without a backfill.

Server/browser spans remain request entry points even with a remote parent.
Performance child timings follow parent ancestry to the nearest local entry
span; separate backend calls in one trace no longer share one timing bucket.
Child lookup is capped at 5,000 rows and exposes `child_data_truncated`.

## Rollout and rollback

1. Apply additive migrations for project links/audits and the disabled project
   flag. The new request-entry index builds concurrently; existing indexes stay.
2. Deploy the backend with `LOGISTER_CROSS_PROJECT_CORRELATIONS=false` (default).
   Existing SDK payloads and readers continue to work.
3. Publish and verify each independently versioned add-on through its normal
   protected-main workflow. Android must publish both core and optional OkHttp
   artifacts before declaring its release complete. Pin the CLI contract to the
   reviewed backend commit. Do not advertise unpublished packages as current.
4. Upgrade a test mobile/backend pair, configure distinct releases/environments,
   and enable the instance flag. In each project, open Settings → Integrations
   → Connected projects and enable related requests. Connect the caller to its
   backend with exact environment mappings.
5. Trigger a synthetic failed request. Confirm outgoing headers, local server
   parent, mobile handled error, backend occurrence, and each deployment. Check
   an unauthorized account/token cannot see the neighbor. Then enable other
   pairs deliberately.

Stop expansion on incorrect matches, permission leakage, query timeouts, or
unexpected missing coverage. Turn off the instance flag or either project flag
for immediate read rollback; disable the client wrapper for propagation rollback.
Keep additive tables/indexes during application rollback. Disconnecting removes
the relationship, not historical telemetry. No destructive cleanup is required.
The instance operator owns enablement and query/coverage monitoring; SDK
maintainers own package publication and application developers own allowlists.

## Verification

- Backend service/request specs cover aliases, conflicts, permissions, token
  scopes, lifecycle, bounds, deployment evidence, and environment remapping.
- `spec/requests/cross_sdk_correlation_spec.rb` ingests synthetic envelopes
  serialized by actual iOS/Android HTTP wrapper tests and Ruby Rails middleware.
  Each fixture records outgoing headers and producer-specific envelopes.
- `spec/services/correlation_clickhouse_spec.rb` runs only with an explicit
  `LOGISTER_TEST_CLICKHOUSE_URL` disposable schema-v2 database. It executes ID
  matching and deduplicated event/span queries and remote-parent entry reads.
- `spec/system/project_correlations_spec.rb` covers connection, occurrence
  navigation, and the related requests frame on desktop and narrow layouts.
- SDK suites exercise actual framework/client wiring, concurrent request scopes,
  strict headers, failed request handles, and redirect origin enforcement.

Async job propagation, heuristic/time-only relationships, automatic source-code
endpoint discovery, and complete distributed waterfall views remain outside
this release. Missing IDs produce an explicit explanation rather than a guess.
