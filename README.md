# Logister

Logister is a free, open source, self-hostable analytics dashboard for your apps: one place to collect application errors, logs, metrics, transactions, and check-ins so your team can see what is going wrong, investigate faster, and ship with more confidence.

Use this repository when you want to run Logister yourself. It provides the web UI, project/API key management, ingest endpoints, and the operational pieces for your own self-hosted instance. `logister.org` is a secondary hosted/public instance of the same product direction, not the primary deployment model.

## Table Of Contents

- [What this repo is for](#what-this-repo-is-for)
- [Public docs](#public-docs)
- [Product functionality](#product-functionality)
- [Self-hosted runtime](#self-hosted-runtime)
- [Integrating apps with Logister](#integrating-apps-with-logister)
- [Running the app locally](#running-the-app-locally)
- [Local development nuances](#local-development-nuances)
- [Project documentation](#project-documentation)
- [Source and related repos](#source-and-related-repos)

## What this repo is for

This app is the self-hosted and self-hostable analytics dashboard for Logister:

- user authentication and project management
- project API keys
- event ingestion over HTTP
- inbox and error-group triage UI
- monitor/check-in visibility
- optional ClickHouse-backed analytics

If you are trying to instrument an application, the language integrations live in separate packages and guides:

- Ruby package for Ruby apps and Rails services: https://github.com/taimoorq/logister-ruby
- Python package for FastAPI, Django, Flask, Celery, workers, and Python logging: https://github.com/taimoorq/logister-python
- JavaScript package for Node, TypeScript, Express, workers, and console capture: https://github.com/taimoorq/logister-js
- .NET package for .NET 8+ apps, ASP.NET Core services, workers, and C# services: https://github.com/taimoorq/logister-dotnet

## Public docs

Canonical setup and integration docs live on `docs.logister.org`, with self-hosting treated as the primary deployment path.

### Start here

- Overview: https://docs.logister.org/
- Getting started: https://docs.logister.org/getting-started/
- Product guide: https://docs.logister.org/product/
- Self-hosting: https://docs.logister.org/self-hosting/

### Operations

- Local development: https://docs.logister.org/local-development/
- Deployment config: https://docs.logister.org/deployment/
- ClickHouse: https://docs.logister.org/clickhouse/
- HTTP API: https://docs.logister.org/http-api/

### Integrations

- Ruby integration: https://docs.logister.org/integrations/ruby/
- .NET integration: https://docs.logister.org/integrations/dotnet/
- Python integration: https://docs.logister.org/integrations/python/
- JavaScript integration: https://docs.logister.org/integrations/javascript/
- CFML integration: https://docs.logister.org/integrations/cfml/

When changing setup, deployment, or integration guidance, update the public docs first and keep this README focused on repository orientation.

## Product functionality

Use the product guide when you want the user-facing map of what Logister helps teams do:

- https://docs.logister.org/product/

At a high level, Logister helps teams run their own observability hub, connect services, triage grouped errors, inspect event context and related logs, review metrics/logs/transactions/check-ins, watch scheduled work, understand performance and release health, and share project visibility with teammates.

## Self-hosted runtime

Logister runs as a Rails app with this baseline infrastructure:

- Web/API: Ruby on Rails with Puma/Thruster
- Primary database: PostgreSQL
- Cache + job queue backend: Redis
- Background processing: Sidekiq worker process
- Optional analytics store: ClickHouse
- Optional bot protection: Cloudflare Turnstile
- Optional transactional email: Amazon SES
- Optional consent-gated analytics: Google Analytics or Cloudflare Web Analytics

The basic self-host flow is:

1. Boot the self-hosted Logister app.
2. Create a project in Logister.
3. Generate an API key for that project.
4. Connect an app using one of the supported integrations or direct HTTP ingestion.
5. Verify events appear in the inbox.

## Integrating apps with Logister

Use the guide that matches the app you want to connect:

| Integration | Best for | Package / path |
|----------|-------------|-------------|
| Ruby | Rails and Ruby apps | `logister-ruby` + https://docs.logister.org/integrations/ruby/ |
| .NET / ASP.NET Core | .NET 8+ apps, ASP.NET Core services, workers, and C# services | `logister-dotnet` packages `Logister` and `Logister.AspNetCore` + https://docs.logister.org/integrations/dotnet/ |
| Python | FastAPI, Django, Flask, Celery, Python services, and native Python logging capture | `logister-python` + https://docs.logister.org/integrations/python/ |
| JavaScript / TypeScript | JavaScript and TypeScript services with optional Express middleware and console capture | `logister-js` + https://docs.logister.org/integrations/javascript/ |
| CFML | Lucee and Adobe ColdFusion | direct HTTP ingestion + https://docs.logister.org/integrations/cfml/ |
| Direct HTTP API | Custom clients and unsupported runtimes | https://docs.logister.org/http-api/ |

## Running the app locally

For full local setup, use the public local-development guide:

- https://docs.logister.org/local-development/

The shortest local boot path is:

```bash
cp .env.sample .env
bundle install
bin/rails db:prepare
bin/dev
```

## Local development nuances

A few things are worth knowing before you start changing the app locally:

- `bin/dev` is the normal local entrypoint. It runs the Rails app and watches Tailwind assets.
- Redis-backed behavior matters. Sidekiq, caching, and some operational flows behave more realistically when Redis is available.
- PostgreSQL is the primary system of record. ClickHouse is optional and only needed when you want the higher-scale analytics path.
- The public docs are hosted separately on `docs.logister.org`, so app links to docs intentionally point out of the Rails app.
- On Fly, database preparation should run in the release phase rather than on every web boot.

If you want Docker-backed local infra, or want ClickHouse and PostgreSQL running together locally, use:

- https://docs.logister.org/local-development/
- https://docs.logister.org/clickhouse/

If you are working on the static docs in `cloudflare-docs/`, use [cloudflare-docs/README.md](cloudflare-docs/README.md) for local preview and deployment notes.

The shortest Cloudflare Pages workflow is:

```bash
wrangler pages dev cloudflare-docs
```

Update the static HTML under `cloudflare-docs/`, then deploy with the configured GitHub Actions workflow or a manual command like:

```bash
wrangler pages deploy cloudflare-docs --project-name=<project>
```

Use [cloudflare-docs/README.md](cloudflare-docs/README.md) for the full Cloudflare Pages setup, required secrets, analytics variables, and deployment details.

## Project documentation

| Document | Description |
|----------|-------------|
| [TESTING.md](TESTING.md) | Running tests with RSpec, test layout, and system specs |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute, report bugs, and submit changes |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Community standards and expected behavior |
| [SECURITY.md](SECURITY.md) | Security policy and how to report vulnerabilities |
| [AGENTS.md](AGENTS.md) | Architecture and conventions for AI agents and contributors |
| [docs/cfml_ingestion_guide.md](docs/cfml_ingestion_guide.md) | GitHub-facing pointer to the canonical CFML docs |

## Source and related repos

- Logister app: https://github.com/taimoorq/logister
- Ruby package: https://github.com/taimoorq/logister-ruby
- .NET package: https://github.com/taimoorq/logister-dotnet
- Python package: https://github.com/taimoorq/logister-python
- JavaScript package: https://github.com/taimoorq/logister-js
- RubyGems: https://rubygems.org/gems/logister-ruby
- .NET package IDs: `Logister` and `Logister.AspNetCore` (use project references from `logister-dotnet` until NuGet packages are published)
- PyPI: https://pypi.org/project/logister-python/
- npm: https://www.npmjs.com/package/logister-js
