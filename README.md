# Logister

Logister is an open source, self-hosted error monitoring and bug triage app for teams that want a forkable alternative to Bugsnag, Sentry, and Bugzilla-style workflows. It gives teams one place to collect application errors, logs, metrics, transactions, and check-ins so they can see what is going wrong, assign ownership, investigate faster, and ship with more confidence.

Use this repository when you want to run Logister yourself or fork it for your own needs. It provides the web UI, project/API key management, ingest endpoints, background jobs, release automation, GHCR and Docker Hub images, and operational docs for your own self-hosted instance. `logister.org` is a secondary hosted/public instance of the same product direction, not the primary deployment model.

## Table Of Contents

- [What this repo is for](#what-this-repo-is-for)
- [Public docs](#public-docs)
- [Product functionality](#product-functionality)
- [Self-hosted runtime](#self-hosted-runtime)
- [Integrating apps with Logister](#integrating-apps-with-logister)
- [Running the app locally](#running-the-app-locally)
- [Local development nuances](#local-development-nuances)
- [License](#license)
- [Brand and trademark](#brand-and-trademark)
- [Project documentation](#project-documentation)
- [Source and related repos](#source-and-related-repos)

## What this repo is for

This app is the self-hosted and self-hostable analytics dashboard for Logister:

- user authentication and project management
- project API keys
- event ingestion over HTTP
- cross-app dashboard overview with server-backed explorer charts
- inbox and error-group triage UI with team assignment
- Bugzilla-style issue ownership paired with Bugsnag/Sentry-style application error monitoring
- monitor/check-in visibility
- project lifecycle controls for active, archived, restored, and deleted projects
- project email notifications for first occurrences and daily or weekly digests
- optional ClickHouse-backed analytics
- release versions published as GitHub Releases and Docker images in GitHub Container Registry and Docker Hub

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
- Use cases and comparisons: https://docs.logister.org/use-cases/
- Rails error monitoring: https://docs.logister.org/use-cases/rails-error-monitoring/
- Python error monitoring: https://docs.logister.org/use-cases/python-error-monitoring/
- .NET / ASP.NET Core error monitoring: https://docs.logister.org/use-cases/dotnet-error-monitoring/
- JavaScript / TypeScript error monitoring: https://docs.logister.org/use-cases/javascript-error-monitoring/
- ColdFusion / CFML error monitoring: https://docs.logister.org/use-cases/cfml-error-monitoring/
- Docker registry self-hosting: https://docs.logister.org/use-cases/docker-ghcr-self-hosting/
- Error assignment and team triage: https://docs.logister.org/use-cases/error-assignment-team-triage/
- Amazon SES error alert emails and digests: https://docs.logister.org/use-cases/amazon-ses-error-alerts/
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

At a high level, Logister helps teams run their own observability hub, connect services, scan cross-app dashboard signals, triage and assign grouped errors, inspect event context and related logs, review metrics/logs/transactions/check-ins, watch scheduled work, understand performance and release health, archive retired services without losing history, and share project visibility with teammates.

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
- Supported deployment shapes: Fly, Kamal, Docker image, or a Docker Compose-style single-host stack

The basic self-host flow is:

1. Boot the self-hosted Logister app.
2. Create a project in Logister.
3. Generate an API key for that project.
4. Connect an app using one of the supported integrations or direct HTTP ingestion.
5. Verify errors appear in the inbox and non-error telemetry appears in activity, performance, or monitors.

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

The repo uses `.env.sample` as the example environment file. For self-hosted production installs, copy the entries you need into your deploy provider's secret/config store rather than committing a filled-in `.env` file. The public deployment guide explains what each sample entry does and where to get provider values such as PostgreSQL URLs, Redis URLs, SES SMTP credentials, Turnstile keys, ClickHouse credentials, and analytics IDs:

- https://docs.logister.org/deployment/#env-reference

Release images are published to GitHub Container Registry and Docker Hub after CI, Fly deploy, and Fly health checks pass. The production `Dockerfile` still lets you build locally, but self-hosters can usually pull the versioned image instead:

- `ghcr.io/taimoorq/logister:v1.1.0`
- `ghcr.io/taimoorq/logister:latest`
- `ghcr.io/taimoorq/logister:<short-sha>`
- `docker.io/taimoorq/logister:v1.1.0`
- `docker.io/taimoorq/logister:latest`
- `docker.io/taimoorq/logister:<short-sha>`

The self-hosting guide includes a Docker option for either managed PostgreSQL/Redis or a single-host Compose-style stack with optional ClickHouse:

- https://docs.logister.org/self-hosting/#docker

## Local development nuances

A few things are worth knowing before you start changing the app locally:

- `bin/dev` is the normal local entrypoint. It runs the Rails app and watches Tailwind assets.
- The app UI is server-rendered Rails 8 with Hotwire, Turbo, Stimulus, Propshaft, importmap, and Tailwind. Keep new interactive behavior on that path unless there is a strong product reason to do otherwise.
- Redis-backed behavior matters. Sidekiq, caching, and some operational flows behave more realistically when Redis is available.
- PostgreSQL is the primary system of record. ClickHouse is optional and only needed when you want the higher-scale analytics path.
- The public docs are hosted separately on `docs.logister.org`, so app links to docs intentionally point out of the Rails app.
- On Fly, database preparation should run in the release phase rather than on every web boot. If your database provider gives you separate runtime and migration URLs, set `DATABASE_URL` to the runtime URL and `DATABASE_MIGRATION_URL` to the direct migration/admin URL.
- On Fly and other production hosts, keep one Sidekiq worker running. It handles ClickHouse writes, Action Mailer delivery, first-occurrence error alerts, and digest scheduling; no separate cron service is required.

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

## License

Logister's code is released under the [MIT License](LICENSE). You can use, fork, modify, self-host, and redistribute the code, including for commercial purposes, as long as the license notice is preserved.

## Brand and trademark

The Logister name, logo, wordmark, visual identity, and brand assets are not licensed for use in forks, hosted services, redistributed versions, commercial offerings, or other modified distributions. Public forks and rebranded versions should replace Logister branding with their own branding and avoid implying endorsement by the official Logister project. See [TRADEMARKS.md](TRADEMARKS.md).

## Project documentation

| Document | Description |
|----------|-------------|
| [TESTING.md](TESTING.md) | Running tests with RSpec, test layout, and system specs |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute, report bugs, and submit changes |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Community standards and expected behavior |
| [SECURITY.md](SECURITY.md) | Security policy and how to report vulnerabilities |
| [LICENSE](LICENSE) | MIT License for using, forking, modifying, self-hosting, and redistributing the Logister code |
| [TRADEMARKS.md](TRADEMARKS.md) | Logister brand and trademark policy for forks, hosted services, and redistributed versions |
| [AGENTS.md](AGENTS.md) | Architecture and conventions for AI agents and contributors |
| [CHANGELOG.md](CHANGELOG.md) | User-facing app release history |
| [docs/seo-llm-discovery-plan.md](docs/seo-llm-discovery-plan.md) | SEO and LLM discovery plan for product positioning, intent pages, and AI-readable context |
| [docs/seo-llm-measurement-runbook.md](docs/seo-llm-measurement-runbook.md) | Release-time checks for search, AI crawler, GitHub, container registries, and package discoverability |
| [docs/1.1-release-plan.md](docs/1.1-release-plan.md) | 1.1 release scope, gates, and container registry verification plan |
| [docs/1.0-release-plan.md](docs/1.0-release-plan.md) | 1.0 release scope, gates, rollout, and rollback plan |
| [docs/error-assignment-plan.md](docs/error-assignment-plan.md) | Implementation record for team assignment on grouped errors |
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
