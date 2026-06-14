# Logister

Logister is an open source, self-hosted error monitoring and bug triage app for teams that want a forkable alternative to Bugsnag, Sentry, and Bugzilla-style workflows. It gives teams one place to collect application errors, logs, metrics, transactions, spans, and check-ins so they can see what is going wrong, assign ownership, investigate faster, and ship with more confidence.

Use this repository when you want to run Logister yourself or fork it for your own needs. It provides the web UI, project/API key management, ingest endpoints, background jobs, release automation, GHCR and Docker Hub images, and operational docs for your own self-hosted instance. `logister.org` is a secondary hosted/public instance of the same product direction, not the primary deployment model.

## Table Of Contents

- [What this repo is for](#what-this-repo-is-for)
- [Public docs](#public-docs)
- [Product functionality](#product-functionality)
- [Self-hosted runtime](#self-hosted-runtime)
- [Self-host quickstart](#self-host-quickstart)
- [Integrating apps with Logister](#integrating-apps-with-logister)
- [Metrics reference](#metrics-reference)
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
- optional ClickHouse-backed event/span analytics
- optional S3-compatible archive exports for older hot telemetry
- release versions published as GitHub Releases and Docker images in GitHub Container Registry and Docker Hub

If you are trying to instrument an application, the language integrations live in separate packages and guides:

- Ruby package for Ruby apps and Rails services: https://github.com/taimoorq/logister-ruby and https://rubygems.org/gems/logister-ruby
- Python package for FastAPI, Django, Flask, Celery, workers, and Python logging: https://github.com/taimoorq/logister-python and https://pypi.org/project/logister-python/
- JavaScript package for Node, TypeScript, Express, workers, and console capture: https://github.com/taimoorq/logister-js and https://www.npmjs.com/package/logister-js
- .NET package for .NET 8+ apps, ASP.NET Core services, workers, and C# services: https://github.com/taimoorq/logister-dotnet, https://www.nuget.org/packages/Logister, and https://www.nuget.org/packages/Logister.AspNetCore
- Android package for Kotlin and Java Android apps: https://github.com/taimoorq/logister-android and https://central.sonatype.com/artifact/org.logister/logister-android
- iOS package for Swift apps through Swift Package Manager: https://github.com/taimoorq/logister-ios.git and https://github.com/taimoorq/logister-ios/releases/tag/v0.1.0

## Public docs

Canonical setup and integration docs live on `docs.logister.org`, with self-hosting treated as the primary deployment path.

### Start here

- Overview: https://docs.logister.org/
- Getting started: https://docs.logister.org/getting-started/
- Product guide: https://docs.logister.org/product/
- Metrics reference: https://docs.logister.org/metrics/
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
- API reference and Swagger UI: https://docs.logister.org/api-reference/
- OpenAPI YAML: https://docs.logister.org/openapi.yaml
- Postman collection: https://docs.logister.org/postman/logister-api.postman_collection.json

### Integrations

- Ruby integration: https://docs.logister.org/integrations/ruby/
- .NET integration: https://docs.logister.org/integrations/dotnet/
- Python integration: https://docs.logister.org/integrations/python/
- JavaScript integration: https://docs.logister.org/integrations/javascript/
- Android integration: https://docs.logister.org/integrations/android/
- iOS integration: https://docs.logister.org/integrations/ios/
- CFML integration: https://docs.logister.org/integrations/cfml/

When changing setup, deployment, or integration guidance, update the public docs first and keep this README focused on repository orientation.

## Product functionality

Use the product guide when you want the user-facing map of what Logister helps teams do:

- https://docs.logister.org/product/

At a high level, Logister helps teams run their own observability hub, connect services, scan cross-app dashboard signals, triage and assign grouped errors, inspect event context and related logs, review metrics/logs/transactions/spans/check-ins, watch scheduled work, understand performance and release health, archive retired services without losing history, and share project visibility with teammates.

## Self-hosted runtime

Logister runs as a Rails app with this baseline infrastructure:

- Web/API: Ruby on Rails with Puma/Thruster
- Primary database: PostgreSQL
- Cache + job queue backend: Redis
- Background processing: Sidekiq worker process
- Optional analytics store: ClickHouse
- Optional cold archive storage: Amazon S3 or an S3-compatible object store through Active Storage
- Optional bot protection: Cloudflare Turnstile
- Optional transactional email: Amazon SES
- Optional consent-gated analytics: Google Analytics or Cloudflare Web Analytics
- Supported deployment shapes: Fly, Kamal, Docker image, or a Docker Compose-style single-host stack

Use the optional services only when you need them. A practical first production install is one web process, one Sidekiq worker, PostgreSQL, Redis, SMTP if users need email, and HTTPS termination through your platform, proxy, or load balancer.

## Self-host quickstart

This is the shortest production path. Use the public docs when you need provider-specific detail, but follow these steps in order.

1. Provision required services.
   - PostgreSQL for app data and hot telemetry.
   - Redis for Rails cache and Sidekiq jobs.
   - A host that can run one web container and one worker container.

2. Choose an app image.

   ```bash
   docker pull ghcr.io/taimoorq/logister:v2.4.0
   # or
   docker pull docker.io/taimoorq/logister:v2.4.0
   ```

3. Create production config from the sample.

   ```bash
   cp .env.sample .env.production
   ```

4. Set the required production values in your host or secret manager.

   | Variable | What to set |
   |----------|-------------|
   | `RAILS_ENV` | `production` |
   | `RAILS_MASTER_KEY` | Rails credentials key for this deployment |
   | `DATABASE_URL` | PostgreSQL runtime URL |
   | `REDIS_URL` | Redis URL |
   | `LOGISTER_PUBLIC_URL` | Canonical HTTPS app URL |
   | `LOGISTER_ADMIN_EMAILS` | Comma-separated operator emails |
   | `LOGISTER_UPDATE_CHECKS_ENABLED` | Optional, set `false` to disable daily GitHub release checks |

   Public ingestion endpoints are rate limited by default. `POST /api/v1/ingest_events` and `POST /api/v1/check_ins` accept 1,200 requests per minute per API token per endpoint. Missing, invalid, revoked, or archived-project tokens are capped at 120 authentication failures per minute per source IP. Self-hosters can tune those defaults with `LOGISTER_PUBLIC_API_RATE_LIMIT_REQUESTS`, `LOGISTER_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS`, and `LOGISTER_PUBLIC_API_AUTH_FAILURE_RATE_LIMIT_REQUESTS`. App admins listed in `LOGISTER_ADMIN_EMAILS` can also set project-level overrides from project settings.

   Keep real values in your deploy provider, Docker secrets, Fly secrets, Kamal secrets, or another secret manager. Do not commit a filled-in `.env.production`.

5. Prepare the database before the web process receives traffic.

   ```bash
   ./bin/release
   ```

   If your provider gives separate pooled and direct PostgreSQL URLs, set `DATABASE_URL` to the runtime URL and `DATABASE_MIGRATION_URL` to the direct migration URL.

6. Run the two required processes from the same image.

   ```bash
   # Web process
   ./bin/thrust ./bin/rails server

   # Worker process
   bundle exec sidekiq -C config/sidekiq.yml
   ```

7. Add optional services after the baseline works.

   | Optional service | Enable when |
   |------------------|-------------|
   | SMTP / Amazon SES | Users need confirmation, password reset, alerts, or digests |
   | ClickHouse | PostgreSQL-only analytics is not enough for your event volume |
   | S3-compatible storage | You want archive exports before pruning older hot telemetry |
   | Cloudflare Turnstile | Public auth forms need bot protection |
   | Consent-gated analytics | Public product pages need traffic analytics |

8. Verify the install.

   ```text
   /up responds
   Web sign-in works
   Sidekiq starts without Redis errors
   Project creation works
   API key generation works
   A test event appears in the project inbox
   ```

After the baseline is deployed, the day-one product flow is:

1. Create a project in Logister.
2. Generate an API key for that project.
3. Connect an app using one of the supported integrations or direct HTTP ingestion.
4. Verify errors appear in the inbox and non-error telemetry appears in activity, performance, or monitors.

## Integrating apps with Logister

Use the guide that matches the app you want to connect:

| Integration | Best for | Package / path |
|----------|-------------|-------------|
| Ruby | Rails and Ruby apps | `logister-ruby` on RubyGems: https://rubygems.org/gems/logister-ruby + https://docs.logister.org/integrations/ruby/ |
| .NET / ASP.NET Core | .NET 8+ apps, ASP.NET Core services, workers, and C# services | NuGet packages `Logister` and `Logister.AspNetCore`: https://www.nuget.org/packages/Logister + https://www.nuget.org/packages/Logister.AspNetCore + https://docs.logister.org/integrations/dotnet/ |
| Python | FastAPI, Django, Flask, Celery, Python services, and native Python logging capture | `logister-python` on PyPI: https://pypi.org/project/logister-python/ + https://docs.logister.org/integrations/python/ |
| JavaScript / TypeScript | JavaScript and TypeScript services with optional Express middleware and console capture | `logister-js` on npm: https://www.npmjs.com/package/logister-js + https://docs.logister.org/integrations/javascript/ |
| Android | Kotlin and Java Android apps | `org.logister:logister-android` on Maven Central: https://central.sonatype.com/artifact/org.logister/logister-android + https://docs.logister.org/integrations/android/ |
| iOS | Swift iOS apps | `Logister` through Swift Package Manager: https://github.com/taimoorq/logister-ios.git + https://docs.logister.org/integrations/ios/ |
| CFML | Lucee and Adobe ColdFusion | direct HTTP ingestion + https://docs.logister.org/integrations/cfml/ |
| Manual / HTTP API | Custom clients, scripts, workers, and unsupported runtimes | https://docs.logister.org/http-api/ + https://docs.logister.org/api-reference/ |

All first-party add-ons send the same core telemetry families into the main app so the inbox, activity, performance, Insights, and monitor views stay consistent across languages.

Mobile add-ons use the same ingest envelope with platform-specific setup:

| Platform | Package manager | Package / URL | Docs |
|----------|-------------|-------------|-------------|
| Android | Maven Central / Gradle | `org.logister:logister-android:0.1.0` | https://docs.logister.org/integrations/android/ |
| iOS | Swift Package Manager | `https://github.com/taimoorq/logister-ios.git` with product `Logister` | https://docs.logister.org/integrations/ios/ |

The public HTTP APIs return `429 Too Many Requests` with `Retry-After`, `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` headers when a project token exceeds the default 1,200 requests per minute per endpoint. Only app admins, not project owners or shared project members, can set project-level overrides.

The machine-readable API contract lives in [docs/openapi.yaml](docs/openapi.yaml), and the ready-to-import Postman collection lives in [docs/postman/logister-api.postman_collection.json](docs/postman/logister-api.postman_collection.json). The Cloudflare docs build copies both artifacts to the public docs host.

| Capability | Ruby | .NET | Python | JavaScript / TypeScript | CFML / HTTP |
|----------|----------|----------|----------|----------|----------|
| Errors | Automatic Rails/manual Ruby errors | ASP.NET Core middleware and manual exceptions | FastAPI, Django, Flask, Celery, logging exceptions, manual exceptions | Express middleware, console error capture, manual exceptions | `Application.cfc.onError()` or direct error payloads |
| Logs | `Logister.report_log` / messages | `CaptureMessageAsync` | Python `logging` integration and manual messages | `instrumentConsole()` and manual messages | Direct `log` events |
| Metrics | Numeric metrics with value/unit context and DB timing options | `CaptureMetricAsync` | `capture_metric` with value, unit, level, and fingerprint | `captureMetric` | Direct `metric` events |
| Transactions | Rails/request or manual transactions | ASP.NET Core request transactions and manual transactions | Framework request/task timing and manual transactions | Express/request, browser, job, and manual transactions | Direct request/job transaction events |
| Spans | Manual spans and opt-in Rails request spans | Manual spans and opt-in ASP.NET Core request spans | Manual spans and opt-in FastAPI/Django/Flask request spans | Manual spans, Express request spans, and browser page/resource spans | Direct root and child span events |
| Check-ins | Cron, scheduler, and worker check-ins | Worker and scheduled-task check-ins | Celery and manual check-ins | Job/script check-ins | Direct monitor check-ins |

## Metrics reference

Logister collects errors, logs, metrics, transactions, spans, and check-ins, then derives chartable Insights metrics from those signals. The full reference lives in [docs/metrics-reference.md](docs/metrics-reference.md) and covers:

- the raw telemetry families and the fields Logister reads from each one
- built-in Insights series such as `events.total`, `errors.count`, `transactions.p95`, `db.query.avg`, and `db.query.p95`
- custom metric series using `metric:<name>` counts and `metric_value:<name>` averages from numeric `context.value`
- span and transaction timing segments for app, database, render, HTTP, cache, queue, resource, and other work
- filter dimensions such as environment, release, and safe custom context attributes

## Running the app locally

Use this when you are working on the app itself. For a production deployment, use the self-host quickstart above instead.

Prerequisites:

- Ruby `4.0.5`
- PostgreSQL
- Redis for production-like cache and job behavior
- Node/npm for npm-backed assets

The shortest local boot path is:

```bash
cp .env.sample .env
npm ci
bundle install
bin/rails db:prepare
bin/dev
```

Run a worker in a second terminal when you need background jobs:

```bash
bundle exec sidekiq -C config/sidekiq.yml
```

Use Docker-backed local infrastructure when you do not already have PostgreSQL, Redis, or ClickHouse available:

```bash
docker compose --profile docker-db up -d
bin/rails db:prepare
```

The repo uses `.env.sample` as the example environment file. For self-hosted production installs, copy the entries you need into your deploy provider's secret/config store rather than committing a filled-in `.env` file. The public deployment guide explains the full environment reference:

- https://docs.logister.org/deployment/#env-reference

Release images are published to GitHub Container Registry and Docker Hub after CI, Fly deploy, and Fly health checks pass. The production `Dockerfile` still lets you build locally, but self-hosters can usually pull the versioned image:

- `ghcr.io/taimoorq/logister:v2.4.0`
- `ghcr.io/taimoorq/logister:latest`
- `ghcr.io/taimoorq/logister:<short-sha>`
- `docker.io/taimoorq/logister:v2.4.0`
- `docker.io/taimoorq/logister:latest`
- `docker.io/taimoorq/logister:<short-sha>`

The release workflow also supports an optional Quay.io mirror. Add `QUAY_USERNAME` and `QUAY_TOKEN` as GitHub Actions secrets to publish `quay.io/<namespace>/logister` with the same version, `latest`, and short-SHA tags. If the Quay login is a robot account such as `namespace+robot`, the workflow derives the image namespace automatically; set `QUAY_NAMESPACE` if you want to override it.

The self-hosting guide includes a Docker option for either managed PostgreSQL/Redis or a single-host Compose-style stack with optional ClickHouse:

- https://docs.logister.org/self-hosting/#docker

## Local development nuances

A few things are worth knowing before you start changing the app locally:

- `bin/dev` is the normal local entrypoint. It runs the Rails app and watches Tailwind assets.
- The app UI is server-rendered Rails 8 with Hotwire, Turbo, Stimulus, Propshaft, importmap, and Tailwind. Keep new interactive behavior on that path unless there is a strong product reason to do otherwise.
- For frontend behavior conventions, use [docs/stimulus-turbo-patterns.md](docs/stimulus-turbo-patterns.md).
- Redis-backed behavior matters. Sidekiq, caching, and some operational flows behave more realistically when Redis is available.
- PostgreSQL is the primary system of record. ClickHouse is optional and only needed when you want the higher-scale analytics path; S3-compatible archive storage is optional and only needed when you want compressed exports of older hot telemetry before pruning.
- The public docs are hosted separately on `docs.logister.org`, so app links to docs intentionally point out of the Rails app.
- On Fly, database preparation should run in the release phase rather than on every web boot. If your database provider gives you separate runtime and migration URLs, set `DATABASE_URL` to the runtime URL and `DATABASE_MIGRATION_URL` to the direct migration/admin URL.
- On Fly and other production hosts, keep one Sidekiq worker running. It handles ClickHouse writes, Action Mailer delivery, first-occurrence error alerts, digest scheduling, and archive/prune tasks you run through Rails; no separate cron service is required for the built-in scheduler jobs.

If you want Docker-backed local infra, or want ClickHouse and PostgreSQL running together locally, use:

- https://docs.logister.org/local-development/
- https://docs.logister.org/clickhouse/

If you are working on the static docs in `cloudflare-docs/`, use [cloudflare-docs/README.md](cloudflare-docs/README.md) for local preview and deployment notes.

The shortest Cloudflare Pages workflow is:

```bash
wrangler pages dev cloudflare-docs
```

Update the static HTML under `cloudflare-docs/`, run `npm ci` and `bin/build-cloudflare-docs` to regenerate metadata and the Pagefind search index, then deploy with the configured GitHub Actions workflow or a manual command like:

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
| [docs/stimulus-turbo-patterns.md](docs/stimulus-turbo-patterns.md) | Hotwire, Turbo, Stimulus, third-party JS, and asset pipeline conventions |
| [docs/metrics-reference.md](docs/metrics-reference.md) | Telemetry families, Insights metrics, add-on support matrix, reporting fields, and collection boundaries |
| [docs/mobile-add-ons.md](docs/mobile-add-ons.md) | Android and iOS package manager setup, SDK usage examples, release mechanics, and mobile telemetry boundaries |
| [docs/cloudflare-mobile-integrations-plan.md](docs/cloudflare-mobile-integrations-plan.md) | Product plan for Cloudflare Pages metrics, Android telemetry, iOS telemetry, and project-type-aware dashboards |
| [docs/openapi.yaml](docs/openapi.yaml) | OpenAPI contract for the public ingest and check-in APIs |
| [docs/postman/logister-api.postman_collection.json](docs/postman/logister-api.postman_collection.json) | Postman collection with example requests for every supported event family |
| [docs/sdk-parity-and-self-monitoring.md](docs/sdk-parity-and-self-monitoring.md) | SDK option parity and internal Logister self-monitoring checklist |
| [docs/telemetry-storage-retention.md](docs/telemetry-storage-retention.md) | ClickHouse readiness, S3 archive exports, hot telemetry pruning, and Redis retry cleanup |
| [docs/seo-llm-discovery-plan.md](docs/seo-llm-discovery-plan.md) | SEO and LLM discovery plan for product positioning, intent pages, and AI-readable context |
| [docs/seo-llm-measurement-runbook.md](docs/seo-llm-measurement-runbook.md) | Release-time checks for search, AI crawler, GitHub, container registries, and package discoverability |
| [docs/2.0-release-plan.md](docs/2.0-release-plan.md) | 2.0 release scope, UI continuity plan, Insights GA checklist, and stable release gates |
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
- Android package: https://github.com/taimoorq/logister-android
- iOS package: https://github.com/taimoorq/logister-ios
- RubyGems: https://rubygems.org/gems/logister-ruby
- NuGet base package: https://www.nuget.org/packages/Logister
- NuGet ASP.NET Core package: https://www.nuget.org/packages/Logister.AspNetCore
- PyPI: https://pypi.org/project/logister-python/
- npm: https://www.npmjs.com/package/logister-js
- Maven Central: https://central.sonatype.com/artifact/org.logister/logister-android
- Swift Package Manager release: https://github.com/taimoorq/logister-ios/releases/tag/v0.1.0
