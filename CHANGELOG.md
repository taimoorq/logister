# Changelog

All notable changes to Logister will be documented in this file.

## v1.1.0 - 2026-05-10

### Added

- Root MIT License for the Logister code, giving community users clear permission to use, fork, modify, self-host, and redistribute it.
- Logister trademark and brand policy clarifying that forks and redistributed versions must replace Logister branding and must not use the Logister name, logo, wordmark, visual identity, or brand assets without permission.
- GHCR post-deploy runbook for verifying release publication, package visibility, image tags, and public image pulls after the next release deploy.
- SEO and LLM discovery plan documenting Logister's product positioning, intent-page strategy, structured data, robots, and measurement work.
- Use-case and comparison docs for self-hosted error monitoring, Sentry alternatives, Bugsnag alternatives, and Bugzilla-style app error triage.
- Runtime-focused SEO docs for Rails, Python, .NET / ASP.NET Core, JavaScript / TypeScript, and CFML error monitoring.
- Operations-focused SEO docs for Docker/GHCR self-hosting, team error assignment workflows, and Amazon SES error alert emails or digest summaries.
- Expanded `llms-full.txt` files for the app and docs domains so AI tools can read a denser product, stack, release, license, brand, and comparison context.
- Account-wide dashboard event drilldown from explorer filters so chart slices can open the matching recent events.

### Changed

- Repositioned the homepage, About page, public docs, SEO metadata, robots rules, and `llms.txt` around Logister as a forkable, self-hosted error monitoring and bug triage alternative.
- Updated self-hosting and AI-readable release references for the next `v1.1.0` Docker image published to GitHub Container Registry.
- Expanded public project documentation so self-hosters understand the supported release distribution path, permissive code license, and separate Logister brand policy.
- Standardized the public product definition around open source, self-hosted error monitoring and bug triage for teams evaluating forkable alternatives to Bugsnag, Sentry, and Bugzilla-style workflows.
- Added the public `llms.txt` and `llms-full.txt` files to the app sitemap so AI-readable product context is easier to discover.

## v1.0.0 - 2026-05-10

### Added

- First stable self-hosted Logister release, packaging the current Rails 8 app, PostgreSQL, Redis, Sidekiq, Fly deployment, and Cloudflare Pages docs path as the supported operating model.
- Cross-app dashboard explorer powered by server-side aggregate endpoints, Stimulus, and vendored ECharts through the Rails asset pipeline.
- Team assignment for grouped errors, including assignee chips, assign-to-me actions, dashboard shortcuts, project workload counts, and inbox filters for everyone, assigned-to-me, unassigned, or a teammate.
- Project lifecycle controls for archive, restore, and delete flows, with archived projects kept accessible from archived/all views.
- Project error email notifications through SMTP/Amazon SES, including first-occurrence alerts and daily or weekly digest preferences.
- Runtime-aware event detail views for Ruby, .NET, Python, JavaScript/TypeScript, and CFML, including prominent request method and URL/path context when events provide it.
- Static public docs, repo docs, `llms.txt`, and a dedicated 1.0 release plan that describe the shipped product and self-hosting path.

### Changed

- Reworked the dashboard, project overview, inbox, error detail, and top navigation around active projects, assigned work, project signals, and efficient drill-downs.
- Moved larger debugging payloads into fixed-height, scrollable panes so long traces and context blocks are easier to consume.
- Reduced dashboard, project, and inbox data fan-out with bounded Rails aggregates, Redis-backed cache windows, and server-side chart/filter endpoints.
- Archived projects now disappear from active dashboards, active project lists, and the top navigation, and archiving revokes active API tokens.
- Expanded the self-hosting environment sample and deployment docs so operators can map each supported Rails, PostgreSQL, Redis, Sidekiq, SES, ClickHouse, Turnstile, analytics, and Cloudflare docs setting to the provider value they need.
- Documented Docker self-hosting options for running the production image with separate web and worker containers, managed services, or a single-host Compose-style stack with optional ClickHouse.
- Added GitHub Container Registry publishing for release images, including version, latest, and short-SHA tags after CI, Fly deploy, and Fly health checks pass.
- Release automation now treats the top changelog entry as the GitHub Release body after CI, CodeQL, Fly deploy, and Fly health checks pass.

### Fixed

- Added and verified database indexes for high-volume dashboard, projects, inbox, assignment, notification, and search paths.
- Hardened dashboard explorer filtering and JSON rendering to satisfy CI security checks while keeping self-hosted installs free of checked-in secrets.
- Fixed dashboard chart rendering issues caused by stale assets, sparse timeline buckets, and Stimulus state collisions.
- Tightened docs, testing, and architecture notes so self-hosters and contributors can understand the current app surface without relying on tribal knowledge.

## v0.1.8 - 2026-05-10

### Added

- Cross-app dashboard explorer powered by server-side aggregate endpoints, Stimulus, and vendored ECharts through the Rails asset pipeline.
- Interactive Event mix filtering for the Needs attention feed, so users can switch between open errors and recent log, metric, transaction, or check-in context without leaving the dashboard.
- Error assignment controls for project users, including assignee chips, assign-to-me actions, dashboard shortcuts, project workload counts, and inbox filters for everyone, assigned-to-me, unassigned, or a teammate.
- Project archiving and restoring from project settings, keeping historical data available while hiding archived apps from active dashboard and project views.
- A Logister-styled reset-password form that matches the sign-in, sign-up, forgot-password, and confirmation pages.

### Changed

- Reworked the dashboard layout so high-priority attention items, event mix, explorer slice totals, and project signals each have clearer space and mobile-friendly behavior.
- Moved project counts into a bottom Project overview row beside Projects at a glance, tying the counts to the project shortcuts instead of crowding the top of the page.
- Reduced dashboard data fan-out by serving chart data from bounded Rails aggregates and keeping client-side chart behavior focused on rendering and filtering.
- Archived projects now disable existing API tokens and block new token creation until the project is restored.

### Fixed

- Added dashboard, project, and inbox database indexes for large event volumes, including inbox stage search, and removed expensive cache-version scans from dashboard/project overview loads.
- Fixed dashboard chart rendering issues caused by stale assets, sparse timeline buckets, and Stimulus state collisions.
- Hardened dashboard explorer filtering and JSON rendering to satisfy CI security checks while keeping self-hosted installs free of checked-in secrets.

## v0.1.7 - 2026-05-10

### Added

- Project error email notifications through Amazon SES, including first-occurrence alerts and daily or weekly digest preferences per project.
- Branded HTML and plain-text error emails with project, environment, release, occurrence, and triage links for self-hosted installs.
- Product, self-hosting, and privacy documentation updates that cover the current deployment and notification setup.

### Changed

- Redesigned the dashboard overview around account-wide reliability signals, recent activity, event mix, monitor health, and compact project links.
- Tightened the dashboard and project inbox headers with compact status strips for faster scanning across apps and within one app.
- Added a compact projects-page overview and optimized dashboard, project, and inbox aggregation for larger event volumes.
- Switched outbound email configuration away from the old SendGrid-specific adapter and onto standard Rails SMTP settings for SES-backed delivery.
- Consolidated CI, release, and Fly deploy checks so successful production deploys publish the newest changelog entry as the latest GitHub release.

### Fixed

- Hardened Fly deploys around release commands, worker sizing, health checks, and serialized machine updates.
- Added high-volume dashboard and inbox indexes, including Redis-friendly cache-version indexes and trigram search indexes for error-group lookup.
- Adjusted CI gating so deploys wait for the required app checks and GitHub's default CodeQL setup before publishing a release.

## v0.1.6 - 2026-05-01

### Added

- .NET-specific event collection support for `logister-dotnet`, including richer exception, request, route, status code, and optional cookie context.
- .NET exception detail views that mirror the familiar ASP.NET developer exception layout with stack, query, cookie, header, and routing sections.
- Streamline Freehand icon assets in the Rails asset pipeline for consistent project, navigation, and action icons.

### Changed

- Refined the error inbox into a more compact, scannable layout with horizontal filters, denser rows, secondary metadata rows, and tooltip-backed details.
- Updated project cards and the dashboard to make project headers and error counts easier to scan and navigate.
- Simplified project creation by removing the manual slug field and generating slugs automatically from project names.

### Fixed

- Required CI and CodeQL checks to pass before Fly deploys run from `main`.
- Fixed Fly production builds so Streamline icon generation has its Node dependencies during asset precompile without shipping `node_modules` in the runtime image.

## v0.1.5 - 2026-04-22

### Added

- Python-specific event rendering for richer exception details, runtime metadata, chained exceptions, and Python log events.
- JavaScript-specific event rendering for chained exception details and dedicated JavaScript log event views.
- Activity-list summaries for Python and JavaScript log events so logger metadata is visible before opening an event.
- Additional helper and request spec coverage around Python and JavaScript event presentation logic.

### Changed

- Expanded project integration guidance for Python and JavaScript to cover Python logging capture and JavaScript console capture.
- Updated Cloudflare-hosted docs and in-app docs copy so Python and JavaScript guides reflect the current SDK capabilities and audience-specific positioning.
- Improved product wording for Python and JavaScript setup flows so each language guide speaks to its primary runtime patterns.

### Fixed

- Closed the gap where Python and JavaScript log events were shown in generic event views instead of language-aware detail panels.

## v0.1.4 - 2026-04-21

### Added

- JavaScript / TypeScript project integration type for apps using the `logister-js` package.
- JavaScript integration guidance in project settings, activity, performance, and monitor flows.
- Public JavaScript integration docs under `docs.logister.org/integrations/javascript/`.

### Changed

- Updated project integration helpers and labels so `logister-js` projects link to the right external documentation.
- Expanded the static docs and SDK README content so `logister-js` clearly links back to the main Logister app and self-hosted backend.

### Fixed

- Closed the docs gap where JavaScript projects could be selected in the app without a matching public integration guide.

## v0.1.3 - 2026-04-21

### Added

- Standalone static documentation site under `cloudflare-docs/` for hosting on Cloudflare Pages.
- Cloudflare Pages deployment workflow plus repo configuration for automatic docs publishes from `main`.
- Static docs SEO assets including page-level canonical metadata, `robots.txt`, and a dedicated docs sitemap.
- Shared app helper for linking to the external `docs.logister.org` site from Rails views and project integration surfaces.

### Changed

- Moved the public product and integration docs out of the Rails app and made `docs.logister.org` the canonical docs host.
- Updated in-app docs links to open the external docs site in a new tab so users keep their place in the Logister app.
- Shifted GitHub-facing documentation to point at the hosted docs site instead of duplicating setup content in repo markdown.
- Limited the app sitemap to Rails-hosted marketing/legal pages and left docs discovery to the static docs sitemap.

### Fixed

- Legacy `/docs` Rails routes now issue permanent redirects to the Cloudflare-hosted docs pages for SEO continuity.
- Removed the duplicate Rails docs implementation so the app no longer has two competing sources of documentation truth.
- Tightened docs migration coverage around external links, redirects, and canonical docs URLs.

## v0.1.2 - 2026-04-21

### Added

- Project integration types with support for both `Ruby gem` and `CFML` project setup flows.
- Public documentation section under `/docs` with guides for getting started, self-hosting, HTTP API usage, and Ruby/CFML integrations.
- CFML-focused exception rendering with support for structured `tagContext`, exception detail fields, and request/CGI metadata.
- Docs helper and request coverage for public docs pages, layout assets, section anchors, and copy-enabled code blocks.
- Release configuration in `config/release.yml` and GitHub release publishing on successful Fly deploys.

### Changed

- Split project guidance across dedicated subpages so settings, activity, monitors, and performance pages can link to the right integration docs.
- Updated the docs layout to use the app’s shared asset-loading helpers and standard Hotwire/importmap boot path.
- Refined docs content into a more consistent guide format with overview, setup flow, verification, and next-step sections.
- Simplified the docs top navigation so the left sidebar is the primary documentation navigation surface.
- Limited Fly runtime boot to process startup and left database setup to the Fly release phase.

### Fixed

- API key creation and revocation now return users to project settings so one-time tokens are visible when generated.
- Project sharing redirects now return to settings instead of dropping users back into the inbox.
- Docs asset loading in development now respects the Propshaft/Tailwind setup instead of relying on stale precompiled CSS.
- Resolved docs helper lint issues and tightened request specs around docs layout assets and Turbo metadata.

## v0.1.1 - 2026-04-17

### Added

- Public `CHANGELOG.md` tracking for future open source releases.
- Focused specs for JSON-LD escaping, API key token generation, and ClickHouse client health caching.
- New database migrations covering operational timestamp indexes.

### Changed

- Renamed the repo release log to the more standard open source `CHANGELOG.md` format.
- Extracted ingest event context helpers into a dedicated concern to keep the model leaner.
- Refined dashboard, project, and release aggregation helpers for clearer count and query behavior.
- Made the API key token prefix configurable with `LOGISTER_API_KEY_PREFIX`.
- Refactored the ClickHouse HTTP transport into an explicit connection helper.

### Fixed

- Escaped JSON-LD output safely in the application layout helper path.
- Reduced repeated per-release aggregation work when building project release cards.
- Cached ClickHouse health probes to avoid repeated synchronous checks.
- Reduced static analyzer noise around synchronous ClickHouse transport and inline token generation.

## v0.1.0 - 2026-04-17

### Added

- Public changelog tracking for the repository.
- Timestamp indexes for API keys, check-in monitors, error groups, and user auth lifecycle fields.

### Changed

- Extracted ingest event context helpers into a dedicated concern to keep the model smaller and easier to maintain.
- Refined dashboard and release aggregation count helpers to keep summary queries straightforward and consistent.
- Made the API key token prefix configurable with `LOGISTER_API_KEY_PREFIX`.
- Cached ClickHouse health probes briefly to reduce repeated synchronous network checks.

### Fixed

- Escaped JSON-LD output safely in the application layout helper path.
- Reduced repeated per-release aggregation work when building project release cards.

## Template

Copy this block for the next release and place it above older entries.

```md
## v0.1.1 - 2026-04-18

### Added

- Short summary of new features.

### Changed

- Short summary of behavior or internal changes.

### Fixed

- Short summary of bug fixes.
```
