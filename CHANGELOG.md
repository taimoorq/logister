# Changelog

All notable changes to Logister will be documented in this file.

## Unreleased

### Added

- TBD

### Changed

- TBD

### Fixed

- TBD

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
