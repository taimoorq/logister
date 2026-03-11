# Logister

Logister is a Rails + PostgreSQL service for collecting application errors and metrics from other Rails apps.

PostgreSQL is the control-plane database (users/projects/api keys). Event analytics can be dual-written to ClickHouse for high-scale querying.

## Table of contents

- [Open source and self-hosting](#open-source-and-self-hosting)
- [Project documentation](#project-documentation)
- [Core flow](#core-flow)
- [Runtime stack](#runtime-stack)
- [Prerequisites](#prerequisites)
- [Self-host quickstart (local)](#self-host-quickstart-local)
- [Local development setup](#local-development-setup)
- [Development seed data](#development-seed-data)
- [What operators must provide](#what-operators-must-provide)
- [Production self-hosting checklist](#production-self-hosting-checklist)
- [Provider-specific config files](#provider-specific-config-files)
- [Local infrastructure with Docker](#local-infrastructure-with-docker)
- [Cloudflare Turnstile](#cloudflare-turnstile)
- [Ingest API](#ingest-api)
- [Check-in API](#check-in-api)
- [ClickHouse (optional, recommended for scale)](#clickhouse-optional-recommended-for-scale)
- [Companion gem](#companion-gem)

## Open source and self-hosting

This repository is open source and can be self-hosted.

- Source: https://github.com/taimoorq/logister
- Companion gem: https://github.com/taimoorq/logister-ruby
- RubyGems: https://rubygems.org/gems/logister-ruby

## Project documentation

| Document | Description |
|----------|-------------|
| [TESTING.md](TESTING.md) | Running tests with RSpec, test layout, and system specs |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute, report bugs, and submit changes |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Community standards and expected behavior |
| [SECURITY.md](SECURITY.md) | Security policy and how to report vulnerabilities |
| [AGENTS.md](AGENTS.md) | Architecture and conventions for AI agents and contributors |
| [docs/RAILS_ARCHITECTURE_REVIEW.md](docs/RAILS_ARCHITECTURE_REVIEW.md) | Rails/DHH-style architecture review of the app |

## Core flow

1. Users sign up at `logister.org` (Devise authentication).
2. Users create one or more projects (each project maps to a monitored app).
3. Users generate API keys per project.
4. Client apps send events to `POST /api/v1/ingest_events` using an API token.
5. Events are stored and visible in the dashboard.

## Runtime stack

Logister runs as a Rails web app with these components:

- Web/API: Ruby on Rails (Puma)
- Primary database: PostgreSQL
- Cache + job backend: Redis
- Background processing: Sidekiq
- Optional analytics store: ClickHouse
- Optional bot protection: Cloudflare Turnstile
- Optional transactional email: SendGrid API

## Prerequisites

- Ruby `4.0.1`
- PostgreSQL `>= 14`
- Redis `>= 7`
- (Optional) ClickHouse for analytics

## Self-host quickstart (local)

### 1) Clone and configure

```bash
git clone https://github.com/taimoorq/logister.git
cd logister
cp .env.sample .env
bundle install
```

### 2) Prepare database

```bash
bin/rails db:prepare
```

### 3) Start app

```bash
bin/dev
```

`bin/dev` attempts to ensure local Redis is running (via `docker compose up -d redis`) so cache and Sidekiq-backed features work locally.

### 4) Optional local infra

- Start ClickHouse + Redis:

```bash
bin/dev-infra
```

- Start ClickHouse + Redis + Postgres in Docker:

```bash
bin/dev-infra --with-postgres
```

- Initialize ClickHouse schema (if enabled):

```bash
cat docs/clickhouse_schema.sql | curl "http://127.0.0.1:8123" --data-binary @-
```

## Local development setup

```bash
cp .env.sample .env
bundle install
bin/rails db:prepare
bin/dev
```

`bin/dev` now attempts to ensure a local Redis instance is running (via `docker compose up -d redis`) so cache + Sidekiq-backed features can run locally.

Or start infra + app together:

```bash
bin/dev-infra
```

`LOGISTER_EMAIL_FROM` defaults to `support@logister.org` and is used by both app mailers and Devise emails.

For confirmation emails in production, configure SendGrid API key:

```bash
SENDGRID_API_KEY=<sendgrid_api_key>
```

## Development seed data

The app ships with idempotent sample seeds for development only.

Run:

```bash
bin/rails db:seed
```

What gets seeded:

- 3 confirmed users (`alice`, `bob`, `carol`)
- 3 projects with shared memberships
- Active and revoked API keys
- Sample events across `error`, `metric`, `transaction`, `log`, and `check_in`
- Error groups in multiple states (`unresolved`, `resolved`, `ignored`, `archived`)
- Check-in monitor scenarios (`ok`, `missed`, `error`)

Demo sign-in credentials:

- `alice@example.com / password123`
- `bob@example.com / password123`
- `carol@example.com / password123`

## What operators must provide

At minimum (production):

- `RAILS_MASTER_KEY` (Rails credentials decryption)
- `DATABASE_URL` (PostgreSQL connection)
- `REDIS_URL` (Redis/Redis Cloud connection)
- `LOGISTER_ADMIN_EMAILS` (bootstrap admin access, comma-separated emails)

Typically also provided:

- `LOGISTER_EMAIL_FROM` (sender for auth/system emails)
- `SENDGRID_API_KEY` (if sending email via SendGrid)

Optional integrations:

- ClickHouse:
  `LOGISTER_CLICKHOUSE_ENABLED`,
  `LOGISTER_CLICKHOUSE_URL`,
  `LOGISTER_CLICKHOUSE_DATABASE`,
  `LOGISTER_CLICKHOUSE_EVENTS_TABLE`,
  `LOGISTER_CLICKHOUSE_USERNAME`,
  `LOGISTER_CLICKHOUSE_PASSWORD`
- Turnstile:
  `LOGISTER_TURNSTILE_ENABLED`,
  `LOGISTER_TURNSTILE_SITE_KEY`,
  `LOGISTER_TURNSTILE_SECRET_KEY`
- TermsFeed Cookie Consent + Google Analytics:
- TermsFeed Cookie Consent + analytics:
  `LOGISTER_COOKIE_CONSENT_ENABLED`,
  `LOGISTER_ANALYTICS_ENABLED`,
  `COOKIECONSENT_SCRIPT_URL`,
  `COOKIECONSENT_WEBSITE_NAME`,
  `COOKIECONSENT_PRIVACY_POLICY_URL`,
  `GOOGLE_TAG_ID`,
  `CLOUDFLARE_WEB_ANALYTICS_TOKEN`

Google Analytics and Cloudflare Web Analytics are consent-gated in the app and
only enabled when `LOGISTER_COOKIE_CONSENT_ENABLED=true` plus their respective
ID/token env var is set.
Analytics tags render automatically in production. For local/staging verification,
set `LOGISTER_ANALYTICS_ENABLED=true`.

## Production self-hosting checklist

1. Set required secrets:
   - `RAILS_MASTER_KEY`
   - `DATABASE_URL`
   - `REDIS_URL` (Redis Cloud example: `rediss://default:<password>@<host>:<port>/0`)
2. Configure outbound email:
   - `SENDGRID_API_KEY`
   - `LOGISTER_EMAIL_FROM`
3. Choose deployment method:
   - Use included `Dockerfile`, or
   - Use Kamal config in `config/deploy.yml`
4. Run migrations on deploy:
   - `bin/rails db:migrate`
5. Enable background jobs in production:
   - Sidekiq already configured to use `REDIS_URL`
6. Optional: enable ClickHouse dual-write with `LOGISTER_CLICKHOUSE_ENABLED=true`
7. Set at least one admin email:
   - `LOGISTER_ADMIN_EMAILS=you@example.com`
8. Optional security hardening:
   - Turn on Turnstile (`LOGISTER_TURNSTILE_ENABLED=true`)
   - Enable SSL/host authorization in `config/environments/production.rb`
9. Optional consent + analytics setup:
   - Configure TermsFeed consent banner:
     - `LOGISTER_COOKIE_CONSENT_ENABLED=true`
     - `COOKIECONSENT_WEBSITE_NAME=<your_website_name>`
     - `COOKIECONSENT_PRIVACY_POLICY_URL=https://your-domain.example/privacy`
   - Configure your Google tag ID: `GOOGLE_TAG_ID=G-XXXXXXXXXX`
   - Configure your Cloudflare token:
     `CLOUDFLARE_WEB_ANALYTICS_TOKEN=<your_token>`
   - For non-production testing, set: `LOGISTER_ANALYTICS_ENABLED=true`
   - In self-hosted/open-source deployments, always use your own IDs/tokens

## Provider-specific config files

This repo keeps safe provider config in git and avoids committing secrets.

- Fly.io config: `fly.toml` (tracked, non-secret deployment config)
- Fly.io template: `fly.toml.example` (reference copy)
- Keep secrets in GitHub Actions/Fly secrets, not in repo files.

## Local infrastructure with Docker

If you use Postgres.app locally, run only ClickHouse and Redis:

```bash
docker compose up -d clickhouse redis
bin/rails db:prepare
```

Equivalent one-command startup (infra + Rails): `bin/dev-infra`

If you want Postgres in Docker too:

```bash
docker compose --profile docker-db up -d
bin/rails db:prepare
```

Equivalent one-command startup with Docker Postgres: `bin/dev-infra --with-postgres`

Then initialize ClickHouse schema:

```bash
cat docs/clickhouse_schema.sql | curl "http://127.0.0.1:8123" --data-binary @-
```

## Cloudflare Turnstile

This app uses the `rails_cloudflare_turnstile` gem with Devise custom controllers.

Turnstile is enabled on Devise sign-in and sign-up when these env vars are set:

```bash
LOGISTER_TURNSTILE_ENABLED=true
LOGISTER_TURNSTILE_SITE_KEY=
LOGISTER_TURNSTILE_SECRET_KEY=
```

The widget is rendered in the Devise forms via `cloudflare_turnstile`, and tokens are verified server-side via `validate_cloudflare_turnstile`.

## Ingest API

- Endpoint: `POST /api/v1/ingest_events`
- Auth header: `Authorization: Bearer <api_token>`
- Alternate auth: `X-Api-Key: <api_token>`

Example payload:

```json
{
  "event": {
    "event_type": "error",
    "level": "error",
    "message": "NoMethodError in CheckoutService",
    "fingerprint": "checkout-nomethoderror",
    "occurred_at": "2026-02-14T12:00:00Z",
    "context": {
      "environment": "production",
      "request_id": "abc123",
      "metadata": {
        "user_id": 42
      }
    }
  }
}
```

Supported `event_type` values: `error`, `metric`, `transaction`, `log`, `check_in`.

For database load metrics from the companion gem, metric events use `message: "db.query"` and context fields like `duration_ms`, `name`, and `sql`.

Transaction events should include `transaction_name`, `duration_ms`, and correlation fields (`trace_id`, `request_id`) in context.

Log events should include correlation identifiers in context when available (`trace_id`, `request_id`, `session_id`, `user_id`) so error views can pivot to surrounding logs.

## Check-in API

- Endpoint: `POST /api/v1/check_ins`
- Auth header: `Authorization: Bearer <api_token>`

Example payload:

```json
{
  "check_in": {
    "slug": "nightly-reconcile",
    "status": "ok",
    "expected_interval_seconds": 900,
    "environment": "production",
    "release": "2026.03.02"
  }
}
```

## ClickHouse (optional, recommended for scale)

### Environment variables

```bash
LOGISTER_CLICKHOUSE_ENABLED=true
LOGISTER_CLICKHOUSE_URL=http://127.0.0.1:8123
LOGISTER_CLICKHOUSE_DATABASE=logister
LOGISTER_CLICKHOUSE_EVENTS_TABLE=events_raw
LOGISTER_CLICKHOUSE_USERNAME=default
LOGISTER_CLICKHOUSE_PASSWORD=
REDIS_URL=redis://127.0.0.1:6379/0
# For Redis Cloud / redis.io in production:
# REDIS_URL=rediss://default:<password>@<host>:<port>/0
```

`LOGISTER_CLICKHOUSE_URL` supports both:
- native ClickHouse HTTP endpoint (for example `https://<host>:8443`)
- ClickHouse Query API endpoint (for example `https://queries.clickhouse.cloud/service/<id>/run?format=JSONEachRow`)

### Schema and dashboard SQL

- Schema and materialized view: `docs/clickhouse_schema.sql`
- Starter dashboard queries: `docs/clickhouse_dashboard_queries.sql`

### Health endpoint

- `GET /health/clickhouse`
- Returns `200` when disabled or healthy; `503` when enabled but unreachable.

### Payload mapping to ClickHouse columns

- `project_id` <- authenticated API key's project
- `api_key_id` <- authenticated API key id
- `occurred_at` <- `event.occurred_at` (fallback set in Rails)
- `event_type` <- `event.event_type`
- `level` <- `event.level`
- `fingerprint` <- `event.fingerprint` (or generated fallback)
- `message` <- `event.message`
- `environment` <- `event.context.environment` (fallback `Rails.env`)
- `service` <- `event.context.service` (fallback project slug)
- `release` <- `event.context.release`
- `exception_class` <- `event.context.exception_class` or `event.context.exception.class`
- `transaction_name` <- `event.context.transaction_name`
- `tags` <- `event.context.tags`
- `context_json` <- full `event.context`

## Companion gem

`logister-ruby` is released at `0.1.2` and provides error + metric reporting for Rails apps.

- GitHub: https://github.com/taimoorq/logister-ruby
- RubyGems: https://rubygems.org/gems/logister-ruby

To upgrade a client app:

```ruby
gem "logister-ruby", "~> 0.1.2"
```

Enable database timing metrics in the client initializer:

```ruby
Logister.configure do |config|
  config.capture_db_metrics = true
  config.db_metric_min_duration_ms = 10.0
  config.db_metric_sample_rate = 1.0
end
```
