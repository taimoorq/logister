# Cloudflare And Mobile Integrations Plan

This plan tracks the next Logister product expansion: Cloudflare Pages site metrics, Android app telemetry, iOS app telemetry, and project-type-aware dashboards in the Rails app.

## Canonical Repos

| Area | Home | Purpose |
| --- | --- | --- |
| Rails hub | `logister/` | Stores projects, API keys, raw telemetry, imports, dashboards, Insights, settings, and docs. |
| Android SDK | `logister-android/` | Android package add-on, published through the Android package ecosystem. Build all Android SDK work here. |
| iOS SDK | `logister-ios/` | iOS package add-on, published through Swift Package Manager tags. Build all iOS SDK work here. |
| Cloudflare Pages import | `logister/` | Pull-based importer and project settings live in the Rails app; no separate SDK repo is needed. |

Cloudflare Pages does not need a separate `logister-cloudflare-pages` repo for the first milestone. The integration is a Rails-side pull importer that talks to Cloudflare APIs and writes normalized Logister events. There is no user-installed package to publish yet. If we later add a Pages Function, Worker, or deployment-hook helper that users install in a Cloudflare project, the appropriate package manager would be npm because Cloudflare Pages/Workers tooling is JavaScript and TypeScript centered.

## Source Types

Logister should support these project integration kinds:

- `cloudflare_pages`: pull Cloudflare Pages and Web Analytics data into Logister.
- `android`: accept app-side telemetry from `logister-android` and optionally import aggregate Android vitals.
- `ios`: accept app-side telemetry from `logister-ios` and optionally import aggregate App Store Connect analytics.

The existing ingest API can already receive errors, logs, metrics, transactions, spans, and check-ins. The first product milestone is therefore project taxonomy, setup copy, and normalized context fields rather than a new ingest endpoint.

## Cloudflare Pages

Cloudflare Pages projects can use Web Analytics, and Cloudflare can automatically add the Web Analytics JavaScript snippet to a Pages site on the next deployment after it is enabled. Cloudflare also exposes aggregated analytics through the GraphQL Analytics API at a single GraphQL endpoint.

Target metrics:

- Web Analytics totals: page views, visitors, top paths, referrers, browsers, devices, countries, and performance signals where available.
- Pages deployments: latest production deployment, build status, failed deployments, build duration, branch, commit hash, deployment URL, aliases, and custom domains.
- Operational signals: failed builds as Logister log or error events, deployment success as log events, traffic rollups as metric events.

Initial Rails work:

- Add a `cloudflare_pages` project kind.
- Add project settings for Cloudflare account ID, Pages project name, optional zone/site IDs, and a secret reference for the Cloudflare API token.
- Add a scheduled importer that writes platform metrics as Logister `metric` events with names such as `cloudflare.page_views`, `cloudflare.visitors`, `cloudflare.deployment_build_ms`, and `cloudflare.deployment_failed`.
- Add a Cloudflare panel on the project overview with traffic, top pages, and deployment health.
- Keep project integration type immutable after creation, because imported and pushed telemetry is shaped for the selected data source.
- Index platform telemetry on project/platform/time, project/service/time, and Cloudflare deployment/time in addition to the existing project/type/metric indexes.

References:

- https://developers.cloudflare.com/pages/how-to/web-analytics/
- https://developers.cloudflare.com/analytics/graphql-api/

## Android

Android should have two data paths:

- Push telemetry from apps through `logister-android`.
- Optional pull imports from Google Play Developer Reporting API for aggregate Android vitals.

`logister-android` is built in `logister-android/` and published as an Android library through Maven Central with coordinates `org.logister:logister-android`. The Android SDK uses the existing Logister ingest envelope so the Rails app remains the system of record.

SDK targets:

- Uncaught exception capture.
- App start and screen transactions.
- Network request timing spans.
- Manual errors, logs, metrics, transactions, spans, and check-ins.
- Release and build metadata: package name, version name, version code, build type, OS version, API level, device manufacturer/model, locale, and installation/session IDs.
- Privacy defaults that avoid raw headers, tokens, request bodies, and other sensitive data.

Google Play import targets:

- ANR rate, crash rate, error counts, error issues, error reports, slow rendering rate, slow start rate, excessive wakeup rate, low memory kill rate, stuck background wakelock rate, and anomalies where permissions allow.

Initial Rails work:

- Add an `android` project kind.
- Add project settings for package name, Play app name, optional service account secret reference, and SDK API token guidance.
- Add Android overview panels for crash/ANR health, slow starts, slow rendering, active releases, devices, and recent app-side errors.

References:

- https://github.com/taimoorq/logister-android
- https://central.sonatype.com/artifact/org.logister/logister-android
- https://developer.android.com/build/publish-library/upload-library
- https://developers.google.com/play/developer/reporting/reference/rest

## iOS

iOS should have two data paths:

- Push telemetry from apps through `logister-ios`.
- Optional pull imports from App Store Connect Analytics Reports API for aggregate store and app analytics.

`logister-ios` is built in `logister-ios/` and published through Swift Package Manager from the public GitHub repository and semantic version tags. CocoaPods can be added later only if there is real demand.

SDK targets:

- Exception and crash breadcrumbs within the limits of safe iOS runtime behavior.
- App launch and screen transactions.
- URLSession timing spans.
- Manual errors, logs, metrics, transactions, spans, and check-ins.
- Release and build metadata: bundle ID, app version, build number, iOS version, device model, locale, and installation/session IDs.
- Privacy defaults that avoid raw headers, tokens, request bodies, and other sensitive data.

App Store Connect import targets:

- App Store discovery and engagement, downloads, purchases where relevant, app usage, retention, subscriptions where relevant, and crash reports when available through the analytics/reporting surface.
- Treat App Store Connect data as delayed aggregate telemetry. It is useful for trends, not real-time incident detection.

Initial Rails work:

- Add an `ios` project kind.
- Add project settings for bundle ID, App Store app ID, issuer/key IDs, private key secret reference, and SDK API token guidance.
- Add iOS overview panels for sessions, app versions, launches, crashes, downloads, retention, and recent app-side errors.

References:

- https://github.com/taimoorq/logister-ios
- https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/introducingpackages/
- https://developer.apple.com/help/app-store-connect-analytics/overview/analytics-reports-api

## Normalized Context

The SDKs and importers should prefer these shared fields:

| Field | Cloudflare Pages | Android | iOS |
| --- | --- | --- | --- |
| `platform` | `cloudflare_pages` | `android` | `ios` |
| `service` | Pages project name | Package name | Bundle ID |
| `release` | Deployment hash or branch/release label | Version name and version code | Version and build number |
| `environment` | `production`, `preview`, or branch | `production`, `staging`, `debug`, or custom | `production`, `staging`, `debug`, or custom |
| `session_id` | Web session if present | App session ID | App session ID |
| `user_id` | Optional signed-in user ID | Optional app user ID | Optional app user ID |
| `device_model` | Browser device category if known | Manufacturer/model | Device model |
| `os_version` | Browser/OS if known | Android version/API level | iOS version |
| `screen_name` | Page path | Activity, Fragment, or screen name | View controller or screen name |

Metric names should stay stable and low-cardinality. Put high-cardinality identifiers in context only when they are useful for investigation and safe to store.

## Rails Work Phases

1. Project taxonomy and setup UI
   - Add `cloudflare_pages`, `android`, and `ios` integration kinds.
   - Update project picker cards, project labels, icons, setup copy, empty states, factories, and helper specs.
   - Confirm `logister-android/` and `logister-ios/` are named as the SDK homes.

2. SDK scaffolds
   - Android: create Gradle project, Kotlin-first helpers with Java interop, basic client, event payloads, and tests.
   - iOS: create Swift Package layout, basic client, event payloads, and tests.
   - Keep the payload contract aligned with `docs/metrics-reference.md`.
   - Keep package dependencies updateable through Dependabot and the workspace update/check helper.

3. Platform import settings
   - Add encrypted or secret-reference configuration for Cloudflare, Google Play, and App Store Connect.
   - Add project settings forms and validation.
   - Add importer jobs with rate limiting, last-import cursors, and explicit failure logs.

4. Project-type dashboards
   - Keep Overview, Activity, Performance, Insights, Monitors, and Settings as the main rails.
   - Add source-specific overview panels and metric presets.
   - Add custom empty states that explain what the relevant SDK or importer will populate.

5. Public docs and release flow
   - Add public integration docs for Cloudflare Pages, Android, and iOS.
   - Add package publishing runbooks for Maven Central and Swift Package Manager.
   - Add release notes and SDK parity checks.

## Public Repo And Secret Policy

All SDK/add-on repos are intended to be public. Source, examples, tests, and
docs should stay generic and should never include real Logister project API
keys, Cloudflare tokens, Google Play service-account keys, App Store Connect
private keys, signing keys, `.env` files, or local machine paths.

Current package-secret posture:

- `logister-js`: npm trusted publishing; no `NPM_TOKEN` repository secret is needed.
- `logister-python`: PyPI trusted publishing; no PyPI token repository secret is needed.
- `logister-ruby`: RubyGems trusted publishing; no RubyGems API key repository secret is needed.
- `logister-dotnet`: NuGet publishing uses `NUGET_API_KEY`; verified with `gh secret list -R taimoorq/logister-dotnet`.
- `logister-android`: Maven Central publishing uses the verified `org.logister` namespace and GitHub Actions secrets for Central Portal tokens plus the in-memory GPG signing key. The tag workflow uploads a signed deployment to Sonatype Central Portal with automatic release to Maven Central sync. Version `0.1.1` is public at `org.logister:logister-android`.
- `logister-ios`: Swift Package Manager distribution from a public repo does not need a package registry secret. The tag workflow verifies the package and creates the matching GitHub Release.

When a release workflow does need a credential, set it through the GitHub CLI
instead of source control:

```bash
gh secret set SECRET_NAME --repo taimoorq/repository-name
```

## First Milestone

The first milestone is complete when:

- Rails accepts the three new project integration kinds.
- New projects can be created as Cloudflare Pages, Android, or iOS projects.
- Setup and empty-state copy tells users where the telemetry will come from.
- `logister-android/` and `logister-ios/` contain starter README docs that identify them as the canonical package repos.
- `docs/mobile-add-ons.md` explains package manager install paths, release mechanics, and how to use mobile telemetry effectively.
- No importer credentials or package publishing secrets are stored in source control.

## Progress

### 2026-06-01

- Added `cloudflare_pages`, `android`, and `ios` project integration kinds in the Rails app.
- Added project picker metadata, labels, icons, setup guide copy, activity empty states, factories, and focused Rails specs for the new integration kinds.
- Confirmed `logister-android/` is the canonical Android SDK repo and scaffolded it as a Gradle Android library with Kotlin-first helpers over a Java-compatible client for the existing Logister ingest envelope.
- Confirmed `logister-ios/` is the canonical iOS SDK repo and scaffolded it as a Swift Package Manager library with an async Swift client for the existing Logister ingest envelope.
- Added initial Android/iOS helpers for errors, logs, metrics, transactions, spans, and check-ins.
- Added the Android Gradle wrapper plus JUnit tests for metric, span, and exception envelopes.
- Added a generic Rails `ProjectIntegrationSetting` model/table, Cloudflare Pages settings form, update endpoint, and Cloudflare importer job/service placeholder.
- Decided Cloudflare Pages stays Rails-owned for now rather than a separate package repo; npm remains the right package manager if a user-installed Cloudflare Pages/Worker helper is added later.
- Locked project integration type after creation and added platform telemetry indexes for `platform`, `service`, Cloudflare `deployment_id`, and due importer settings.
- Added public-repo hygiene for the Android and iOS SDK repos: MIT licenses, security policies, CI workflows, local secret scans, stricter ignores for signing/credential files, and generic README guidance.
- Added a Kotlin facade and Kotlin tests for `logister-android` so Kotlin apps can configure the SDK with builder lambdas while Java apps can still use the same underlying client classes.
- Added Maven Central publishing configuration and a tag-based Android release workflow for `org.logister:logister-android`, using GitHub Actions secrets for Central Portal credentials and GPG signing.
- Made the Android and iOS repositories public, protected `main`, restricted PR creation to collaborators, enabled secret scanning/push protection, and restricted GitHub Actions permissions.
- Published the iOS Swift Package tag `v0.1.1` and verified the Android `v0.1.1` release workflow publishes successfully to Maven Central after the Central Portal token was corrected.
