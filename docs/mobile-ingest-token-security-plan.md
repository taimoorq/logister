# Mobile Ingest Token Security Plan

This plan replaces long-lived Logister API keys in Android and iOS apps with
short-lived mobile ingest tokens minted by a trusted backend.

## Goals

- Never compile a long-lived Logister project API key into an APK or IPA.
- Keep server project API keys available for backend services, CI, deployments,
  and token minting.
- Allow mobile SDKs to send telemetry only with short-lived, scoped tokens.
- Enforce token scope on the Logister backend, not only in mobile SDK code.
- Reject telemetry that conflicts with token-bound identity fields.
- Test the backend and both mobile SDKs across expiry, revocation, scope,
  refresh, malformed token, and token-provider failure cases.

## Backend Contract

Add `POST /api/v1/mobile_ingest_tokens`.

Only a valid server project API key may call this endpoint. The endpoint returns
one plaintext token once, stores only a digest, and records the token as a child
of the server API key and project.

Mobile ingest tokens are:

- project-scoped
- platform-scoped to `android` or `ios`
- limited to `/api/v1/ingest_events` and `/api/v1/check_ins`
- short-lived, defaulting to 15 minutes
- optionally event-type scoped
- invalidated by token expiry, explicit revocation, parent API key revocation,
  or project archive
- bound to immutable context fields such as `platform`, `service`,
  `environment`, `release`, and `session_id`

When a mobile token is used, Logister injects the bound fields into accepted
telemetry and rejects payloads that try to override them with conflicting values.

## SDK Contract

Android and iOS SDKs must no longer accept a long-lived API key. Each SDK
requires a token provider that fetches short-lived mobile ingest tokens from the
customer's backend.

The SDKs cache tokens until they are close to expiry, refresh before sending,
and fail the telemetry call without crashing the host app when a provider cannot
return a valid token.

## Implementation Order

1. Add the Rails mobile token model, migration, auth support, minting endpoint,
   context enforcement, and request/model tests.
2. Update `logister-android` to use a token-provider API, with tests for cache,
   refresh, invalid tokens, and provider failure.
3. Update `logister-ios` with the same token-provider contract and test matrix.
4. Update Rails setup copy, SDK README files, and public docs to describe the
   backend token issuer path.
5. Run focused backend, Android, and iOS test suites before release.
