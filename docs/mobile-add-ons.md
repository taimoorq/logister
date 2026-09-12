# Mobile add-ons and Rails contracts

Use an Android or iOS project for mobile telemetry. Project type is locked after
creation because setup, payload interpretation and investigation views depend on
it. This maintainer guide maps the mobile boundary; the public runtime guides own
installation examples:

- [Android setup](https://logister.org/docs/integrations/android/)
- [iOS setup](https://logister.org/docs/integrations/ios/)
- [Add-on compatibility and contracts](https://logister.org/docs/http-api/contracts/)
- [OpenAPI](openapi.yaml) and [telemetry v3 evidence](telemetry_v3_evidence_contract.md)

## Package and release boundaries

Reviewed against Rails `v3.6.11` and public package channels on 2026-09-11.

| Platform | Distribution | Verified behavior |
| --- | --- | --- |
| Android | Maven Central `org.logister:logister-android`; matching GitHub release | `0.5.2` is published with v3 evidence, queue isolation, structured ANR threads and last-sampled memory evidence. The older `0.3.0` baseline supports safe automatic crash capture, historical exits, bounded offline storage and account-bound cleanup, but lacks those newer guarantees. |
| iOS | SwiftPM `https://github.com/taimoorq/logister-ios.git`; semantic Git tag and matching GitHub release | `0.5.0` is published. It includes v3 source evidence, reporting intervals, durable queue/relaunch replay, bounded sampled call trees, canonical measurements and explicit session-start timing. `0.3.0` remains a compatible baseline with safe error policies and transient retries, but lacks those newer guarantees. |

Publication evidence: [Android Maven metadata](https://repo1.maven.org/maven2/org/logister/logister-android/maven-metadata.xml),
[Android release](https://github.com/taimoorq/logister-android/releases/tag/v0.5.2),
and [iOS releases](https://github.com/taimoorq/logister-ios/releases).
The committed [ecosystem catalog](../config/ecosystem-versions.json) remains the
source for generated install pins. A source version or successful CI run alone
is not a published package. Use [ecosystem releases](ecosystem-releases.md) for
current-main release promotion, immutable-tag recovery and registry verification;
do not create manual tags from this guide or assume all packages share a version.
Merge version changes to each protected main branch after review; current-main CI
promotes the immutable tag and dispatches publication. For Android, wait for the
public Maven POM and AAR after Central accepts a deployment instead of uploading
the version again. Recover interrupted publication through `release.yml` on main
with the existing `tag` input; never replace a published tag.

When moving from iOS 0.3 to 0.5, read the package migration notes. Client endpoints
are immutable and MetricKit lifecycle is main-actor owned. Keep the collector
alive and stop it explicitly through the app lifecycle. Android's newer queue
migration discards ambiguous old state instead of adopting it under an unproven
tenant; only claim that behavior for a package that actually contains it.

## Runtime authentication

1. Create a server project API key and keep it in your trusted backend.
2. Authenticate the app/session in that backend and decide whether reporting is allowed.
3. Mint a token with `POST /api/v1/mobile_ingest_tokens`, using the server key.
4. Return the short-lived token and `expires_at` to the SDK's token provider.
5. Configure the SDK with the instance base URL and consistent source context.

The request needs a `mobile_ingest_token` object containing `platform` (`android`
or `ios`), `service` and `environment`. `release` and `session_id` are optional
bindings. `expires_in_seconds` defaults to 900 and must be 60–3,600. The default
allowed event types are `error`, `log`, `metric`, `transaction`, `span` and
`check_in`; a nonempty subset can restrict them.

Rails returns the plaintext token once with its expiry and scope. It accepts
that token only on ingest (including batch) and check-in endpoints. It cannot
mint more tokens, record deployments, upload artifacts or read CLI data. Missing
bound context is filled by Rails; conflicting context returns `422`, a prohibited
event type returns `403`, and expired/revoked credentials return `401`. Revoking
the parent key or archiving the project also invalidates its mobile tokens.

Authorize delayed events against their original build/session. A token bound to
today's release cannot accept an older queued release; do not rewrite source
facts to force a match. Remove account-bound queue entries on logout using the
installed SDK's documented cleanup API. Never embed the project or CLI token in
an APK, IPA or app bundle.

## Identity, evidence and delivery

- Generate one UUID at capture and retain it with the immutable payload for retries.
- Single-event acceptance returns `201`; replay returns `200` and `duplicate: true`.
  Batch acceptance returns `202` with indexed results. Acceptance and downstream
  grouping, monitor updates or analytics completion are separate stages.
- v3 is additive to `/api/v1`, not a new HTTP route. Older mobile envelopes remain
  accepted. Exact `occurred_at`, reporting intervals and `received_only` evidence
  must remain distinguishable; receipt time is not proof of an original event time.
- Manual `captureException` is a handled report. Android uncaught/historical
  evidence and Apple MetricKit diagnostics have different source and fatality semantics.
- iOS 0.5 includes delayed crash, hang, excessive CPU, disk-write and iOS 16+
  slow-launch evidence. Resource diagnostics must not imply a fatal crash without
  source evidence. Keep raw addresses/offsets lossless and sampled roles explicit.
- SDK queues, transient retries and privacy controls vary by version. Queued work
  is not accepted work. Review custom context even when SDK/Rails filters apply.

## Build artifacts and external reports

| Workflow | Authentication and identity | Verify separately |
| --- | --- | --- |
| Android R8 mapping | Owner/admin upload on **Project → Artifacts**, or CLI `artifacts:write`. Match package name and exact version code. | Inventory, observed-build coverage and per-event deobfuscation. `Mapping missing` and `Build unknown` are explicit recovery states. |
| Apple dSYM | Owner/admin upload on **Project → Artifacts**, or CLI `artifacts:write`. Match app/build, binary UUID and architecture; private archive storage and Apple-toolchain workers are needed. | `UUID verified` establishes artifact eligibility; event `Symbolicated`, `Partial` or `Failed` is separate. `Verification blocked` identifies missing tooling. Raw addresses remain available. |
| Google Play | Host service-account secret referenced from project integration settings; integrations worker. | Last success, permitted tracks, release/version-code mapping, report freshness and bounded errors. |
| App Store Connect | Host private-key reference, issuer/key/bundle IDs; integrations worker and a 15-minute sweep or manual sync. | Selected app, report availability, last success, freshness and bounded errors. |

CLI 1.1 adds upload commands. Run `logister doctor`, then request the additive
scope with `logister auth login --artifact-write`. Default read scopes do not
permit uploads; the user must also retain owner/admin access to the project.
Use a separate expiring CI credential and confirm command availability in the
installed CLI. A `201` upload response does not mean coverage refresh,
verification or symbolication has finished.

Provider aggregates remain distinct from SDK occurrences and installation/session
impact. Never sum them or calculate crash-free rates without compatible inputs
and an explicit time window. Source context (`repository`, `commit_sha`, `branch`)
helps GitHub lookup; CI records deployments using the server project key at
`POST /api/v1/deployments`.

## Verification and source ownership

Check first delivery, exact replay, token refresh and release/session bindings
before enabling extra collectors. Then inspect Artifacts, per-event evidence and
provider freshness. Audited manager evidence downloads contain stored unredacted
context with `wire_original: false`, not an original wire-payload archive.

The executable contract owners are:

- `MobileIngestToken`, `MobileIngestTokenValidator`, and `ClientSubmissions::MobileTokenPolicy`.
- `IngestEventPayloadNormalizer`, `TelemetryBatchDecoder`, `TelemetryPayloadLimits`,
  `IngestEventPersistence`, and `TraceSpanPersistence`.
- `TelemetryEvidenceNormalizer`, `MobileTelemetryNormalizer`, and the mobile event enrichments.
- `Api::V1::Cli::ArtifactsController`, `AndroidMappingFile`, and `AppleSymbols::ArtifactUploader`.
- Request specs under `spec/requests/api/v1/` and fixtures/specs under `spec/contracts/`.

Keep public guides, package READMEs, the verified catalog, OpenAPI/Postman copies,
AI maps and release-impact decisions aligned when these boundaries change.
