# Changelog

All notable changes to Logister will be documented in this file.

## Unreleased

### Added

- TBD

### Changed

- TBD

### Fixed

- TBD

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
