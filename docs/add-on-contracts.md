# Maintaining add-on contracts

The [public contract reference](https://logister.org/docs/http-api/contracts/)
helps developers connect SDKs, direct HTTP clients and CI to Rails. This map
identifies the source and validation owners for the same claims. Last reviewed
against `v3.6.11` on 2026-09-11.

## Sources of truth

| Boundary | Implementation and executable evidence | Documentation |
| --- | --- | --- |
| Routes, schemas and status codes | `config/routes.rb`; `app/controllers/api/v1`; `spec/requests/api/v1`; `spec/requests/api/v1/cli_openapi_contract_spec.rb` | `docs/openapi.yaml`, HTTP API guide and generated API download |
| Atomic acceptance and replay | `IngestEventPersistence`, `TraceSpanPersistence`, `Logister::TelemetryBatchAcceptance`; corresponding service/request specs | HTTP API batch section, contract delivery section, Postman batch request |
| Payload limits | `ClientSubmissions::RequestLimits`, `TelemetryBatchDecoder`, `TelemetryPayloadLimits`; decoder and payload-limit specs | HTTP API limits; keep byte/count/depth budgets exact |
| Mobile tokens and evidence | `MobileIngestToken`, `ClientSubmissions::MobileTokenPolicy`, `TelemetryEvidenceNormalizer`; mobile token requests and `spec/contracts/telemetry_v3_evidence_contract_spec.rb` | `docs/mobile-add-ons.md`, v3 schema/contract, Android/iOS guides |
| CLI authentication, capabilities and uploads | `CliAccessToken`, `Logister::CliCapabilities`, CLI base/artifact controllers and request specs | CLI guide, OpenAPI and contract credential section |
| Optional providers | GitHub, Google Play, App Store Connect and artifact services with their request/service specs | Provider setup guides; distinguish configuration, successful sync, coverage and enrichment |
| Server operations | Sidekiq profiles, telemetry jobs/delivery services, retention workers and recovery tests | Deployment guide, Redis/worker and projector-recovery runbooks |
| Package publication | Each registry plus immutable GitHub release; CLI also checks Homebrew/Scoop tarball checksums | `config/ecosystem-versions.json` and `docs/ecosystem-releases.md` |

## Release state and compatibility

The Rails patch series through 3.6.11 preserves existing SDK ingestion and CLI
contracts. New server worker flags are not a signal for clients to change payload
identity, retry bodies or event type. The five optional CLI read groups are
runtime-gated and default off; a newer installed CLI cannot enable them.

Public-channel observations on 2026-09-11 found Ruby 0.4.1, JavaScript 0.4.2,
Python 0.4.0, both .NET packages 0.3.0, iOS 0.5.0 and CLI 1.1.0 on npm/GitHub.
Android Maven/GitHub now expose 0.5.2, including the earlier v3 evidence and
queue changes. The public reference links the evidence and distinguishes these
individual observations from a fully reconciled release set. The older Android
0.3 catalog baseline does not provide the newer collection or queue guarantees.

Generated installation pins remain tied to the committed verified catalog. Do
not replace it with neighboring checkout versions or infer that every CLI
package manager has updated because npm has. Refresh the catalog through the
reviewed reconciliation flow only after required channels agree.

## Review checklist

1. Trace the changed behavior to controllers, normalizers, persistence and specs;
   compare companion APIs against the actual installed/released package.
2. Update the public page owning the task and link to it from runtime setup. Keep
   minimum-version caveats beside examples, especially mobile collection APIs.
3. Distinguish capture, local queueing, HTTP acceptance, downstream completion,
   artifact verification and per-event enrichment.
4. Update Postman source under `docs/postman/`; the build copies it and OpenAPI to
   `cloudflare-docs/`. Keep public/docs AI maps and discovery links consistent.
5. Record independent consumer bump decisions in the release-impact metadata.
   Documentation clarifications alone do not require SDK bumps or runtime activation.
6. Run `bin/build-cloudflare-docs`, `bin/sync-doc-versions --check`,
   `bin/check-release-impact --all`, `bin/check-release-set`, and
   `scripts/publication-safety-check.sh`. Validate changed links, anchors, copyable
   snippets and rendered pages. Run focused existing contract specs for claims
   that changed; use disposable services for database-backed tests.

Docs deployment is separate from Rails deployment. Keep the live docs contract
matched to its published API download and label source-only functionality before
it becomes public setup guidance.
