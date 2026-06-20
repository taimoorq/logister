# Changelog

All notable changes to Logister will be documented in this file.

## v2.7.0 - 2026-06-20

### Added

- Added purpose-based project email notifications for reopened errors, frequent error thresholds, error milestones, assignment and status workflow changes, missed and recovered monitors, project-wide spikes, p95 performance thresholds, release summaries, usage warnings, and retention/archive failures.
- Added a shared project notification dispatcher with per-kind delivery records, dedupe keys, hourly caps, quiet hours, environment/severity/status filters, and SES-compatible notification headers.
- Added monitor, project health, release, workflow, usage, and retention notification jobs, including retention failure emails when archive exports or cleanup need attention.
- Added focused public docs for notification paths, data retention and archive jobs, GitHub source lookup diagnostics, and Cloudflare Pages telemetry/importer settings.
- Added durable docs-authoring guidance for hub pages, focused subpages, and removing completed planning artifacts after shipped behavior is represented in product docs.

### Changed

- Reworked project notification settings into purpose-specific paths so users choose the reason they want email before tuning individual controls.
- Reordered the main dashboard into Overview and Projects tabs, with the Explorer and Needs Attention areas prioritized side by side and project signal summaries moved to the Projects tab.
- Simplified Project Home by removing redundant summary cards and restoring the error-groups view where recent errors had overloaded the page.
- Updated public self-hosting references for the `v2.7.0` release image tag.
- Removed completed planning documents that had become stale after the shipped behavior moved into the app, changelog, docs, tests, and agent guidance.

### Fixed

- Improved GitHub source lookup troubleshooting by documenting attempted repository, path, ref, and runtime-prefix failures such as doubled `app/app` paths.
- Wrapped telemetry archive upload errors with object-key context and surfaced archive failures through retention notification jobs.
- Removed duplicate dashboard/event mix and environment visualizations that repeated other dashboard signals.

### Upgrade Notes

- Run the Rails database migrations before starting the new version; this release expands `project_notification_preferences` with notification path, threshold, filter, quiet-hours, and delivery-limit settings.
- Keep at least one worker process running and SMTP configured before enabling project notification paths that send email.

## v2.6.1 - 2026-06-19

### Added

- Added project-scoped GitHub App installation links so project owners and admins can explicitly link available installations and choose repositories per project.
- Added project admin permissions for integration, team, API key, notification, and data settings without granting destructive project ownership controls.
- Added JSON export for error groups, with summarized occurrence counts by default and an option to include the latest 50 occurrences for AI-assisted diagnosis.

### Changed

- Reworked the project Integrations page around connected repositories, linked installations, available repository selection, and advanced manual repository mappings.
- Updated project navigation so core project pages share a consistent header, with lower-traffic Events, Performance, and Monitors pages grouped under More.
- Updated public self-hosting references for the `v2.6.1` release image tag.

### Fixed

- Prevented GitHub repositories from being auto-connected by project names, sole synced repos, or telemetry guesses; source lookup now waits for an explicit project mapping.
- Fixed Turbo/Stimulus handling for error JSON exports so downloads do not navigate the error detail frame.

## v2.6.0 - 2026-06-18

### Added

- Added a dedicated project Setup page with a setup checklist, API key management, ingest endpoint guidance, and condensed integration instructions.
- Added goal-oriented project navigation with deliberate Streamline icons for Home, Inbox, Events, Performance, Insights, Deployments, Monitors, Setup, and Settings.

### Changed

- Reorganized project Settings into concise General, Notifications, Team, Integrations, Data, Admin, and Danger sections instead of one dense settings surface.
- Reworked project redirects and product tours so creation, API keys, integrations, team management, retention, and admin changes return users to the most relevant Setup or Settings section.
- Renamed user-facing Activity navigation and dashboard copy to Events for logs, metrics, transactions, spans, and check-ins.
- Updated public self-hosting references for the `v2.6.0` release image tag.

## v2.5.0 - 2026-06-18

### Added

- Added GitHub App source repository integration so projects can connect private GitHub repositories, sync accessible repos, and resolve stack frames to source excerpts with GitHub permalinks.
- Added CODEOWNERS-aware source hints and assignment actions when resolved source files match project members.
- Added GitHub issue and pull request links on error groups, including optional GitHub issue creation when the App installation has `issues:write`.
- Added deployment tracking with `POST /api/v1/deployments`, a project Deployments page, and release-to-commit lookup so source excerpts can use the exact deployed commit.
- Added GitHub App setup documentation, OpenAPI/Postman coverage for deployment indexing, and optional `LOGISTER_GITHUB_*` environment settings for self-hosted installs.

### Changed

- Error detail pages now show deployment context, linked GitHub issues/PRs, source lookup diagnostics, and GitHub-backed source excerpts when repository access is configured.
- Ingested events can carry repository, branch, and commit SHA metadata, and Logister can opportunistically index deployment records from telemetry that includes release and commit data.
- Updated public self-hosting references for the `v2.5.0` release image tag.

### Upgrade Notes

- Run the Rails database migrations before starting the new version; this release adds tables for GitHub App installations, synced repositories, source repository mappings, external links, and deployments.
- GitHub source integration is optional. Self-hosted operators who want private source excerpts or GitHub issue creation should configure their own GitHub App with the new `LOGISTER_GITHUB_APP_ID`, `LOGISTER_GITHUB_APP_PRIVATE_KEY`, `LOGISTER_GITHUB_WEBHOOK_SECRET`, and install URL/slug settings.

## v2.4.1 - 2026-06-16

### Added

- Added Rails cache-backed rate limiting for Devise sign-in, sign-up, password reset, and confirmation resend submissions, using source IP and hashed normalized email identities.
- Added an authentication rate-limiting runbook and agent guidance so future Devise throttles keep the same cache, callback ordering, identity hashing, failure behavior, and request-spec coverage.

### Changed

- Updated public self-hosting references for the `v2.4.1` release image tag.

## v2.4.0 - 2026-06-14

### Added

- Added PostgreSQL range partitioning for `ingest_events`, including shadow-table setup, monthly partitions, mirror triggers, batched backfill, cutover preflight checks, validation tasks, and post-cutover constraint validation.
- Added future partition maintenance so operators can create upcoming monthly partitions before new telemetry arrives.

### Changed

- Updated dashboard, project, inbox, event-detail, retention, and ClickHouse handoff paths to carry partition-aware event references and keep UI queries bounded by the new partition structure.
- Optimized recent dashboard and project summary loading to favor recent indexed scopes instead of all-time event scans.
- Updated public self-hosting references for the `v2.4.0` release image tag.

### Fixed

- Removed Brakeman-flagged dynamic SQL from the partitioning migration helpers while preserving backfill and validation behavior.

## v2.3.0 - 2026-05-24

### Added

- Added a guided project creation integration picker with package-manager choices for Ruby, .NET, Python, JavaScript / TypeScript, CFML, and advanced Manual / HTTP API setup.
- Added mobile-friendly scroll regions and responsive authenticated page adjustments so wide tables, charts, event tabs, project settings, admin views, and project pages remain browsable on phone-sized browsers.
- Added public API and metrics documentation surfaces, including OpenAPI 3.1 YAML and a Postman collection in the repo and Cloudflare docs.

### Changed

- Rethemed public marketing and legal pages with the InvestPro-inspired public style while keeping authenticated app pages on their existing product UI.
- Split Rails layouts into public, auth, and authenticated shells with shared partials and layout-specific importmap entrypoints so public and auth pages avoid loading tour assets, app-only controllers, and ECharts.
- Updated page wizards and product tours so non-overview pages focus on page-specific functionality instead of repeating global header and navigation highlights.
- Updated public self-hosting references for the `v2.3.0` release image tag.

### Fixed

- Fixed integration card copy and layout regressions, plus small-screen overflow in project event detail and analytics surfaces.

## v2.2.0 - 2026-05-23

### Added

- Added Redis-backed rate limiting for public ingestion APIs, covering `POST /api/v1/ingest_events` and `POST /api/v1/check_ins` with `429 Too Many Requests`, `Retry-After`, `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` responses.
- Added deployment knobs for accepted public API requests, rate-limit window size, and authentication-failure throttling through `LOGISTER_PUBLIC_API_RATE_LIMIT_REQUESTS`, `LOGISTER_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS`, and `LOGISTER_PUBLIC_API_AUTH_FAILURE_RATE_LIMIT_REQUESTS`.
- Added app-admin-only project-level public API rate-limit overrides so operators listed in `LOGISTER_ADMIN_EMAILS` can tune limits for a single project without granting that control to project owners or shared project members.

### Changed

- Preloaded projects during API token authentication so project-level rate-limit overrides do not add a second project lookup on accepted ingest and check-in requests.
- Updated public self-hosting references for the `v2.2.0` release image tag.

### Fixed

- Routed the Rails app's Probo Cookie Banner API calls through a same-origin proxy to avoid browser CORS failures when the upstream banner service uses credentialed requests.

## v2.1.1 - 2026-05-23

### Changed

- Optimized high-volume inbox and Events browsing with page-specific PostgreSQL indexes for activity cursors, environment and release filters, assigned error groups, and root span duration ordering.
- Reduced inbox and dashboard page payloads by loading lightweight latest-event link data instead of full event context JSON for summary rows.
- Consolidated inbox status counts, cached empty-inbox activity checks, memoized project assignable users, and trimmed Settings page queries so common project pages fetch only rendered columns.
- Expanded development seed data to cover .NET projects, custom metrics, root and child trace spans, retention settings, notification preferences, notification deliveries, and telemetry archive history.
- Prevented development seeds from creating check-in monitors for non-check-in sample events.
- Configured Bullet in development to surface N+1 queries, unused eager loading, and counter-cache suggestions in browser console, page footer, Rails logs, and `log/bullet.log`.
- Updated public self-hosting references for the `v2.1.1` release image tag.

## v2.1.0 - 2026-05-22

### Added

- Highlighted Project Insights chart series and filter options with matching event counts so users can see which choices have data before adding them.

### Changed

- Kept Insights availability checks on cached dashboard payloads and existing indexed scopes so the clearer filter UI does not add extra browser load requests.
- Updated public self-hosting references for the `v2.1.0` release image tag.

### Fixed

- Removed Brakeman-flagged dynamic SQL from Insights availability counts while preserving indexed database queries.

## v2.0.3 - 2026-05-22

### Added

- Added cached release update checks and a dismissible navigation notification so operators can see when a newer Logister version is available.

### Changed

- Updated public self-hosting references for the `v2.0.3` release image tag.

## v2.0.2 - 2026-05-22

### Changed

- Updated public self-hosting references for the `v2.0.2` release image tag.

### Fixed

- Prevented the main dashboard explorer charts from rendering twice during Turbo cached preview visits.

## v2.0.1 - 2026-05-22

### Changed

- Grouped project Telemetry insights and Performance under a single Insights navigation menu so related analysis views are easier to discover.
- Reformatted the project Insights metric picker so each chart series shows labeled source, unit, key, and event details instead of ambiguous badges.
- Updated public self-hosting references for the `v2.0.1` release image tag.

### Fixed

- Fixed authenticated navigation logo rendering so the brand mark keeps its color and detail on dark headers.

## v2.0.0 - 2026-05-22

### Added

- Promoted the 2.0 observability surface to a stable release, covering project Insights, logs, metrics, transactions, spans, check-ins, optional ClickHouse analytics, and S3-compatible telemetry archives.
- Added stable 2.0 release distribution references for GHCR, Docker Hub, and optional Quay images tagged `v2.0.0`, `latest`, and the release commit SHA.

### Changed

- Updated the production runtime to Ruby 4.0.5 and Bundler 4.0.10.
- Pinned the production Docker base to `ruby:4.0.5-slim-bookworm` for a small, stable Debian base with the app's PostgreSQL, libvips, and jemalloc runtime packages.
- Updated self-hosting docs, Cloudflare-hosted docs, AI-readable docs, and homepage metadata so the public release surfaces point at Logister 2.0.

### Fixed

- Verified the 2.0 release candidate under Ruby 4.0.5 with the full RSpec suite and a Docker base-stage build.

## v2.0.0-beta.4 - 2026-05-22

### Changed

- Added first-class span ingestion, PostgreSQL/ClickHouse span storage, and a stacked request load breakdown chart on project Performance pages.
- Added ClickHouse schema readiness checks, idempotent schema load/status tasks, and throttled ClickHouse self-monitoring failure reports to prevent internal event storms.
- Added S3-backed telemetry archive support with compressed JSONL exports, explicit hot pruning tasks, and Redis retry cleanup tooling for stale ClickHouse jobs.
- Reduced Insights database pressure by lengthening dashboard cache windows and lowering metric/dimension catalog sample limits.
- Updated maintained Ruby, .NET, Python, and JavaScript SDK repos with span capture APIs and opt-in request/page-load span instrumentation.
- Linked the app README, static docs, in-app project setup guidance, and AI-readable docs directly to the public RubyGems, NuGet, PyPI, and npm package pages.
- Updated release readiness docs with the current SDK package versions and concrete package-manager verification links.

## v2.0.0-beta.3 - 2026-05-22

### Changed

- Optimized the Insights beta so the page shell renders before aggregate dashboard queries run and ECharts loads only when the Insights controller is active.
- Reduced Insights catalog work by sampling recent custom metric and dimension data for selector discovery while keeping selected dashboard slices served through the cached data endpoint.
- Hardened deploy-time release publishing so GitHub releases and container images are only published for a new top changelog version and skipped on repeat deploys of an already-published version.

## v2.0.0-beta.2 - 2026-05-22

### Changed

- Expanded public docs for the Insights beta with dashboard recipes, instrumentation guidance, custom attribute best practices, and ClickHouse positioning.
- Aligned AI-readable docs with the Insights beta so `llms.txt` and `llms-full.txt` explain the new project dashboard surface.
- Rebuilt the Cloudflare docs sitemap metadata for the beta docs update.

## v2.0.0-beta.1 - 2026-05-21

### Beta

- This prerelease starts the 2.0 dashboard workstream. It is intended for testing the new project Insights experience before the stable 2.0 release.

### Added

- Project Insights dashboard lab that combines Activity, Inbox, and Performance signals into a live ECharts interface.
- Custom metric catalog support so project dashboards can add or remove collected metric series, including numeric `context.value` metric averages.
- Dimension filters for client-reported custom attributes such as tenant, plan, region, or service, with matching attributes visible in the recent event stream.
- Redis-backed caching for repeated Insights dashboard slices so live refresh does not repeatedly recompute the same project/window/filter aggregates.
- ClickHouse read-query support for future high-volume dashboard panels, alongside the existing optional ClickHouse ingest path.

### Changed

- The release workflow now treats hyphenated versions such as `v2.0.0-beta.1` as GitHub prereleases and avoids publishing beta builds as `latest` container tags.

### Fixed

- Added PostgreSQL indexes for release filters, metric-message series, and JSONB custom attribute filtering used by the new Insights interface.

## v1.1.1 - 2026-05-21

### Added

- Client submission monitoring for intake failures, reported through the `logister-ruby` gem so rejected ingest and check-in submissions create sanitized Logister events instead of disappearing into server logs.
- Diagnostics for failed client submissions, including endpoint, status, request metadata, authentication source, token digest prefix, project/API key state when resolvable, payload shape, and validation errors without storing raw bearer tokens.
- Loop protection so Logister does not recursively self-report rejected client-submission monitoring events.
- Self-monitoring for ClickHouse ingest failures and the error digest scheduler, reported through `logister-ruby` logs, metrics, and check-ins.
- Optional Quay.io container image mirroring for release builds when `QUAY_USERNAME` and `QUAY_TOKEN` GitHub Actions secrets are configured.

### Changed

- Updated the Rails app to `logister-ruby` v0.2.4, which moves shared Ruby error enrichment into the gem for other Ruby/Rails apps to use.
- Broadened API intake normalization for CFML/Lucee-style uppercase `EVENT` and `CHECK_IN` envelopes and nested payload keys.
- Standardized SDK option parity around metric value/unit fields and check-in release, interval, trace ID, and request ID fields across the Ruby, .NET, Python, and JavaScript clients.

### Fixed

- CFML events from quria now render stack frames when the payload provides `exception.stacktrace` or `exception.stack_trace` instead of only `tagContext`/`tag_context`.
- Missing envelopes and invalid ingest/check-in payloads now return explicit client errors while also creating internal monitoring events for triage.

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
- SEO and LLM measurement runbook for release-time URL, sitemap, search console, AI crawler, referral, GitHub, GHCR, and SDK package checks.
- AI-readable maintainer and discovery links for release, SEO, and measurement runbooks.
- Completed SEO and LLM release maintenance checklist for keeping homepage, docs, robots, sitemaps, structured data, GitHub, GHCR, and package surfaces aligned in future releases.
- Account-wide dashboard event drilldown from explorer filters so chart slices can open the matching recent events.

### Changed

- Condensed the Cloudflare docs sidebar with accessible collapsible sections so the static docs can grow without overwhelming the navigation.
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
