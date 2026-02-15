# Logister

Logister is a Rails + PostgreSQL service for collecting application errors and metrics from other Rails apps.

PostgreSQL is the control-plane database (users/projects/api keys). Event analytics can be dual-written to ClickHouse for high-scale querying.

## Core flow

1. Users sign up at `logister.org` (Devise authentication).
2. Users create one or more projects (each project maps to a monitored app).
3. Users generate API keys per project.
4. Client apps send events to `POST /api/v1/ingest_events` using an API token.
5. Events are stored and visible in the dashboard.

## Setup

```bash
cp .env.sample .env
bundle install
bin/rails db:prepare
bin/dev
```

Or start infra + app together:

```bash
bin/dev-infra
```

`LOGISTER_EMAIL_FROM` defaults to `support@logister.org` and is used by both app mailers and Devise emails.

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

Supported `event_type` values: `error`, `metric`.

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

## Next milestone

- Build a companion gem (`logister-ruby`) that captures app exceptions and metrics and submits events to this endpoint.
