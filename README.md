# Logister

Logister is a Rails + PostgreSQL service for collecting application errors and metrics from other Rails apps.

PostgreSQL is the control-plane database (users/projects/api keys). Event analytics can be dual-written to ClickHouse for high-scale querying.

## Public documentation

Most user-facing setup and integration guidance now lives in the app documentation instead of this README.

- Overview: https://logister.org/docs
- Getting started: https://logister.org/docs/getting-started
- Self-hosting: https://logister.org/docs/self-hosting
- Local development: https://logister.org/docs/local-development
- Deployment config: https://logister.org/docs/deployment
- HTTP API: https://logister.org/docs/http-api
- ClickHouse: https://logister.org/docs/clickhouse
- Ruby integration: https://logister.org/docs/integrations/ruby
- CFML integration: https://logister.org/docs/integrations/cfml

When updating setup, deployment, or integration guidance, prefer updating the public docs on `logister.org` first and keep this README focused on repository orientation.

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
| [docs/cfml_ingestion_guide.md](docs/cfml_ingestion_guide.md) | GitHub-facing pointer to the canonical CFML docs on `logister.org` |

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

## Companion gem

`logister-ruby` is released at `0.1.2` and provides error + metric reporting for Rails apps.

- GitHub: https://github.com/taimoorq/logister-ruby
- RubyGems: https://rubygems.org/gems/logister-ruby
- Public integration docs: https://logister.org/docs/integrations/ruby

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
