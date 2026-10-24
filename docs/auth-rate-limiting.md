# Authentication Rate Limiting

Logister protects public Devise form submissions with Rails-side rate limits and optional Cloudflare Turnstile. These are separate protections:

- Rate limiting is always part of the Rails app and uses the configured rate-limit Redis role.
- Turnstile is optional bot verification controlled by the `LOGISTER_TURNSTILE_*` environment variables.
- Public API ingestion rate limiting is separate: the coarse guard is Rack middleware and credential-aware limits live in `ClientSubmissionMonitoring`.

## Public API intake guards

Public telemetry submission has three separate counters. Keeping them separate prevents
successful traffic from being mislabeled as an authentication failure while still
protecting PostgreSQL from credential-lookup floods.

| Layer | Default | Identity and scope | Runs |
|-------|---------|--------------------|------|
| Pre-authentication attempt guard | 12,000 per minute | Source IP across all public submission endpoints | Rack middleware, before JSON parsing and credential lookup |
| Accepted submission limit | 1,200 per minute | API key or mobile ingest token, per endpoint | After successful authentication |
| Authentication failure limit | 120 per minute | Source IP across all public submission endpoints | After credential diagnostics determine the failure and project override |

Tune the coarse guard with `LOGISTER_PUBLIC_API_PRE_AUTH_RATE_LIMIT_REQUESTS`.
It is intentionally global rather than project-scoped because no project is trusted
until authentication completes. Project-specific accepted and failure overrides still
apply to their existing post-authentication counters.

Authentication rejection diagnostics use headers and credential metadata only. They do
not summarize request parameters or read a chunked body to calculate its length. The
legacy single-event endpoint also rejects more than 2 MiB of wire input in middleware,
including chunked requests without `Content-Length`, before Rails parses JSON. Batch
ingest uses the same 2 MiB wire cap plus its separate decompressed and envelope limits.

Authentication failures are counted per source IP, and the limit can come from the project a revoked or invalid credential belonged to. Because the caller is not authenticated, those `401` and `429` responses omit the `X-RateLimit-*` headers and the `limit` and `window_seconds` body fields. They keep `Retry-After` and `retry_after`.

## Rate-limit store outages

Every limiter (public API pre-auth, authentication failure and accepted quotas, CLI pre-auth and read limits, CLI device authorization create and token polling, browser approval of CLI login codes, and Devise create actions) counts through `Logister::RateLimitCounter`.

1. The counter increments the shared rate-limit store. The Redis `error_handler` for that store re-raises, so a Redis error is never read as "not limited".
2. If the shared store raises or refuses the write, the counter uses a process-wide `ActiveSupport::Cache::MemoryStore` capped at 16 MiB. Limits then apply per web process instead of across the fleet, so the effective limit is roughly the configured limit times the number of web processes.
3. If the fallback also fails, the counter returns no count and every limiter fails closed: `429 Too Many Requests` with `Retry-After`. Authenticated ingest quotas are included, so no quota becomes unlimited.

Each use of the fallback logs a warning (`rate limit store unavailable for <kind>, using in-process fallback`) and emits `rate_limit_degraded.logister` through `ActiveSupport::Notifications` with `kind`, `store`, `error_class`, and `fallback` (`memory` or `none`). Alert on that event or log line; a steady stream means the rate-limit Redis role is down.

## CLI device approval limits

The signed-in `/cli/device` page is limited per user and per source IP over a 10-minute window:

| Action | Per user | Per IP |
|--------|----------|--------|
| Look up a login code (`GET /cli/device?user_code=...`) | 30 | 60 |
| Approve or deny (`POST /cli/device`) | 10 | 30 |

Opening the empty code entry page is not counted. Limited requests render the code entry page with `429` and `Retry-After: 600`.

## Devise current limits

| Devise action | IP limit | Email limit |
|---------------|----------|-------------|
| Sign in | 10 attempts per minute | 20 attempts per 10 minutes |
| Sign up | 5 attempts per minute and 20 attempts per hour | 3 attempts per hour |
| Password reset instructions | 5 attempts per 10 minutes | 3 attempts per 10 minutes |
| Confirmation resend | 5 attempts per 10 minutes | 3 attempts per 10 minutes |

When a request exceeds a limit, the app returns `429 Too Many Requests` with a `Retry-After` header.

## Implementation rules

Use `DeviseRateLimitGuard` for Devise create actions. It installs prepended controller callbacks so rate limits run before Devise authentication callbacks and before Turnstile can redirect.

Counters use the rate-limit Redis store configured by `REDIS_RATE_LIMIT_URL`, with backward-compatible fallback to `REDIS_URL`. This keeps limits shared across web processes and lets operators isolate them from the general Rails cache. Count through `Logister::RateLimitCounter`; do not call the cache directly from a guard. See [Rate-limit store outages](#rate-limit-store-outages).

Use layered identities:

- Source IP for broad request floods.
- Normalized email address for targeted sign-in, reset, confirmation, and account-creation abuse.

Email identities must be hashed before they are used in cache keys. Do not put raw email addresses, passwords, tokens, or Turnstile responses in rate-limit keys or logs.

Keep responses simple and machine-readable enough for operators:

- Status: `429 Too Many Requests`
- Header: `Retry-After`
- Notification: `rate_limit.action_controller`

## Adding or changing limits

When adding another Devise-facing create action, include `DeviseRateLimitGuard` and declare one or more `rate_limit_devise_create` rules close to the existing Turnstile callback.

Prefer conservative defaults that protect shared resources without blocking normal humans. Use a short IP window for floods and a longer email window for account-targeted abuse.

If limits need to become operator-tunable, add named config values under `Rails.application.config.x.logister` and document the environment variables in `.env.sample`, `README.md`, and this file. Avoid scattering `ENV.fetch` calls through Devise controllers.

## Testing

Rate-limit behavior belongs in request specs under `spec/requests/users/`. Outage behavior uses the `unavailable_rate_limit_store` and `break_rate_limit_fallback_store!` helpers from `spec/support/rate_limit_counter.rb`. Use an in-memory cache store in the spec so test limits are deterministic even though the test environment normally uses `:null_store`.

Coverage should verify:

- The allowed number of requests does not return `429`.
- The next request returns `429`.
- `Retry-After` matches the configured window.
- Email limits normalize case and surrounding whitespace.
