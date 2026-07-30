# Mobile Add-ons Guide

Logister supports mobile app telemetry through two public add-on repositories:

| Platform | Repository | Package manager | Install identity |
| --- | --- | --- | --- |
| Android | https://github.com/taimoorq/logister-android | Maven Central / Gradle | `org.logister:logister-android` |
| iOS | https://github.com/taimoorq/logister-ios | Swift Package Manager | `https://github.com/taimoorq/logister-ios.git` |

Use a dedicated Android or iOS project in the Rails app. Project type is locked
after creation because the stored telemetry, setup guidance, import settings,
and dashboards are shaped for the selected platform.

## Before You Start

1. Create a Logister project with type `Android app` or `iOS app`.
2. Create a server project API key in the project settings page.
3. Store that server key only in your trusted backend or CI/CD environment.
4. Add a backend endpoint that mints short-lived mobile ingest tokens with
   `POST /api/v1/mobile_ingest_tokens`.
5. Set the SDK `baseUrl` to the Logister app host, such as
   `https://logister.example`.
6. Send stable `environment`, `release`, `service`, and session context so
   Logister can group, filter, and correlate events.

Do not compile a Logister project API key into an Android or iOS app. Mobile
SDKs use short-lived mobile ingest tokens fetched from your backend at runtime.

## Mobile Token Issuer

Your backend should authenticate the app/session, decide whether reporting is
allowed, then call Logister with the server project API key:

```http
POST /api/v1/mobile_ingest_tokens
Authorization: Bearer <server-project-api-key>
```

```json
{
  "mobile_ingest_token": {
    "platform": "android",
    "service": "com.example.app",
    "environment": "production",
    "release": "1.4.0+42",
    "session_id": "session-123",
    "expires_in_seconds": 900,
    "allowed_event_types": ["error", "log", "metric", "transaction", "span", "check_in"]
  }
}
```

Logister returns the plaintext token once:

```json
{
  "token": "logister_mobile_...",
  "expires_at": "2026-06-20T18:30:00Z",
  "platform": "android",
  "service": "com.example.app",
  "environment": "production",
  "release": "1.4.0+42",
  "session_id": "session-123",
  "allowed_event_types": ["error", "log", "metric", "transaction", "span", "check_in"]
}
```

Mobile ingest tokens can send ingest events and check-ins only. They cannot
write deployments or mint more tokens. Logister rejects mobile payloads that
try to override token-bound `platform`, `service`, `environment`, `release`, or
`session_id` values.

## Android

Install from Maven Central:

```kotlin
dependencies {
    implementation("org.logister:logister-android:0.3.0")
}
```

Kotlin apps should use the Kotlin helper surface:

```kotlin
import org.logister.android.captureExceptionAsync
import org.logister.android.captureMetricAsync
import org.logister.android.captureMessageAsync
import org.logister.android.captureTransactionAsync
import org.logister.android.LogisterToken
import org.logister.android.LogisterTokenProvider
import org.logister.android.LogisterBreadcrumb
import org.logister.android.LogisterExceptionDataPolicy
import org.logister.android.logisterClient

class AppBackendTokenProvider : LogisterTokenProvider {
    override fun fetchToken(): LogisterToken {
        // Call your backend token issuer and parse token/expires_at.
        return LogisterToken("short-lived-mobile-token", System.currentTimeMillis() / 1000 + 900)
    }
}

val client = logisterClient(
    baseUrl = "https://your-logister-host.example",
    tokenProvider = AppBackendTokenProvider()
) {
    environment("production")
    release("${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}")
    repository("acme/android-app")
    commitSha(BuildConfig.GIT_SHA)
    branch(BuildConfig.GIT_BRANCH)
    packageName(BuildConfig.APPLICATION_ID)
    appVersion(BuildConfig.VERSION_NAME)
    buildNumber(BuildConfig.VERSION_CODE.toString())
    buildType(BuildConfig.BUILD_TYPE)
    application(myApplication)
    exceptionDataPolicy(LogisterExceptionDataPolicy.TYPE_AND_STACKTRACE)
    sessionTracking(true)
    installationTracking(true, rotationDays = 90)
    breadcrumbs(capacity = 50)
    offlineQueue(enabled = true, maxEvents = 30, maxBytes = 512 * 1024, maxAgeDays = 7)
    automaticCrashCapture(true, LogisterExceptionDataPolicy.TYPE_AND_STACKTRACE)
    applicationExitCapture(true)
}

client.addBreadcrumb(
    LogisterBreadcrumb.builder("Checkout opened")
        .category("navigation")
        .data("screen", "Checkout")
        .build()
)

client.captureMessageAsync("Checkout opened") {
    context("screen_name", "Checkout")
    sessionId("session-123")
}

client.captureMetricAsync("cart.item_count", 3, "count")

client.captureTransactionAsync("screen.load", 184.2) {
    context("screen_name", "Checkout")
}

try {
    runCheckout()
} catch (exception: Exception) {
    client.captureExceptionAsync(exception) {
        mechanism("handled_exception")
        handled(true)
    }
}
```

Send spans and check-ins when you want performance waterfalls and monitor
status:

```kotlin
import org.logister.android.captureSpanAsync
import org.logister.android.checkInAsync
import org.logister.android.logisterSpan

client.captureSpanAsync(
    logisterSpan("trace-123", "GET /checkout", 42.5) {
        spanId("span-456")
        parentSpanId("span-root")
        kind("http")
        status("ok")
        context("screen_name", "Checkout")
    }
)

client.checkInAsync("daily-sync", "ok") {
    durationMs(812.4)
    context("expected_interval_seconds", 86_400)
}
```

Version 0.3.0 sends a canonical, versioned mobile contract while retaining the
older flat aliases. Android telemetry should include:

- `platform: "android"`
- `app.package_name`, `app.version_name`, and `app.version_code`
- release as version name plus version code, such as `1.4.0+42`
- `error.mechanism` and `error.handled`; a manual capture defaults to a
  reported/handled exception, not a fatal crash
- `repository`, `commit_sha`, and `branch` when the app build is tied to a
  GitHub repository
- build type, foreground state, and screen/activity when available
- Android API level, OS version, device model, locale, and session ID when safe
- a rotating random installation pseudonym only when installation tracking is
  enabled

Lifecycle sessions, installation tracking, breadcrumbs, the uncaught-exception
handler, Android 11+ historical app-exit capture, and the disk retry queue are
all opt-in. Automatic crashes use the safe type-and-stacktrace policy by default:
throwable messages and cause chains are omitted, and the sanitized envelope is
written to the durable queue before Android's previous crash handler runs.
Historical app exits also omit the raw platform description. The installation
pseudonym is random and rotated; the SDK does not read Android ID, advertising
ID, IMEI, or a hardware serial.

Automatic crash and historical exit capture require the offline queue. Bound it
by count, bytes, and age. Token-provider and transient delivery failures stay
queued until an authenticated launch can call `flushQueuedEventsAsync()`. A
queued response is not accepted until a later server response succeeds. Apps
should call `clearSessionBoundQueuedEvents()` during logout or account
replacement; anonymous automatic crashes remain available for later delivery.

### Android inbox, R8 mappings, and Google Play

Android projects use a stability-specific inbox. Owners can sort by recommended
priority, impact, or newest and filter by mechanism, release/build, Play track,
environment, build type, device, Android/API version, screen, foreground state,
and time window. Affected installation and session counts appear only when the
corresponding pseudonymous identifiers were collected; missing data is shown as
not collected rather than zero.

For minified builds, open **Project settings → Integrations → R8 mappings** and
upload the build's `mapping.txt` with its package name and version code. Mapping
files are private and project-scoped. The issue detail says **Mapping missing**
when no matching build artifact exists.

The optional Google Play panel is in **Project settings → Integrations → Google
Play**. Store the service-account JSON in the host's secret store, enter only its
environment-variable reference in Logister, and grant the reporting identity
the least privilege required for the Play Developer Reporting API. Imported
crash/ANR rates, anomalies, tracks, provenance, freshness, and time zone remain
visually separate from SDK-derived occurrence and installation metrics. The
Play rate metric sets are version-code scoped, so Logister resolves each
permitted track to its active version codes from the release-filter options
before filtering imported rate rows.

## iOS

Add the package by Git URL with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/taimoorq/logister-ios.git", from: "0.3.0")
]
```

Then depend on the library product:

```swift
.product(name: "Logister", package: "logister-ios")
```

Use the async client from app code:

```swift
import Foundation
import Logister

struct AppBackendTokenProvider: LogisterTokenProvider {
    func fetchToken() async throws -> LogisterToken {
        // Call your backend token issuer and parse token/expires_at.
        LogisterToken(
            token: "short-lived-mobile-token",
            expiresAt: Date().addingTimeInterval(900)
        )
    }
}

let client = LogisterClient(
    baseURL: URL(string: "https://your-logister-host.example")!,
    tokenProvider: AppBackendTokenProvider(),
    environment: "production",
    release: "1.4.0+42",
    repository: "acme/ios-app",
    commitSHA: "4f8c2d1",
    branch: "main",
    service: Bundle.main.bundleIdentifier,
    exceptionDataPolicy: .typeAndStacktrace,
    platformContextPolicy: .minimized
)

try await client.captureMessage(
    "Checkout opened",
    options: LogisterEventOptions(
        sessionID: "session-123",
        installationIDHash: "rotating-random-pseudonym",
        distributionChannel: "testflight",
        inForeground: true,
        breadcrumbs: [
            LogisterBreadcrumb(category: "navigation", message: "Opened checkout")
        ],
        context: ["app": .object(["screen": .string("Checkout")])]
    )
)

try await client.captureMetric("cart.item_count", value: 3, unit: "count")

try await client.captureTransaction(
    "screen.load",
    durationMs: 142.7,
    options: LogisterEventOptions(context: ["screen_name": .string("Checkout")])
)
```

Send spans and check-ins when you want performance waterfalls and monitor
status:

```swift
try await client.captureSpan(
    LogisterSpan(
        traceID: "trace-123",
        spanID: "span-456",
        parentSpanID: "span-root",
        name: "GET /checkout",
        kind: "http",
        status: "ok",
        durationMs: 42.5,
        context: ["screen_name": .string("Checkout")]
    )
)

try await client.checkIn(
    "daily-sync",
    status: "ok",
    options: LogisterEventOptions(
        durationMs: 812.4,
        context: ["expected_interval_seconds": .number(86_400)]
    )
)
```

iOS v0.3.0 emits the versioned Apple telemetry contract automatically:

- `platform: "ios"`
- bundle identifier, app version/build, inferred release, process, Apple
  platform, OS version/build, device family/model, architecture, locale, and
  SDK version
- `repository`, `commit_sha`, and `branch` when the app build is tied to a
  GitHub repository
- optional session ID, rotating random installation hash, distribution channel,
  foreground state, screen, and bounded breadcrumbs

Use `platformContextPolicy: .minimized` to omit exact device model, locale,
architecture, and OS build. `exceptionDataPolicy: .typeAndStacktrace` omits raw
error messages and NSError domain/code metadata from handled reports.

`captureException` is always a handled **Reported error**. It is not an
automatic crash handler. To receive OS-delivered crash, hang, CPU-exception,
and disk-write evidence, keep an opt-in collector alive for the app lifetime:

```swift
let metricKitCollector = LogisterMetricKitCollector(
    client: client,
    dataPolicy: .typeAndStacktrace
)
metricKitCollector.start()
```

MetricKit delivery is delayed. Safe mode omits the raw diagnostic payload and
termination reason and bounds the normalized threads and frames. Each diagnostic receives a deterministic event
UUID, and the Rails ingest boundary returns the existing event on redelivery so
occurrence and impact counts remain unchanged. The SDK also makes bounded
transient retries for network failures, HTTP 408/425/429, and 5xx responses.
Persistent offline queueing, automatic screen timing, and URLSession timing are
not included.

Never send IDFA, raw IDFV, serial numbers, or another stable hardware
identifier. Both the SDK and Rails normalizer recursively remove common
aliases. If installation impact is useful, generate and periodically rotate an
app-scoped random pseudonym before hashing it.

### iOS symbols and Apple reports

Project Settings → Integrations has two independent production workflows:

| Workflow | What it does | What to verify |
| --- | --- | --- |
| dSYM coverage | Stores zipped dSYMs in private archive storage and verifies an exact binary UUID and architecture in a background job. | The artifact is `Ready`; `Awaiting tooling` means the worker lacks Apple `dwarfdump` support. Raw addresses remain visible in every state. |
| App Store Connect | Uses an issuer ID, key ID, bundle ID, and a private-key environment-variable reference to fetch Apple's iOS power/performance report on a 15-minute sweep or manual sync. | Last success, selected app, report availability, freshness, and the last bounded error appear in settings. |

App Store aggregates remain separate from SDK and MetricKit event counts. Do
not add them together or derive a crash-free percentage without a compatible
numerator, denominator, and stated time window.

## What Logister Can Display

Both mobile SDKs use the existing Logister ingest envelope, so the same product
views work across platforms:

| Event family | Logister view | Mobile use |
| --- | --- | --- |
| `error` | Inbox and event detail | Exceptions, crashes, and fatal states |
| `log` | Activity and event detail | Breadcrumbs, warnings, and app lifecycle notes |
| `metric` | Insights and activity | Counters, gauges, screen metrics, and platform measurements |
| `transaction` | Performance and Insights | Screen loads, app starts, jobs, and long-running tasks |
| `span` | Performance waterfalls | HTTP calls, database/cache work, and nested operations |
| `check_in` | Monitors and activity | Sync jobs, background tasks, and heartbeat checks |

Use low-cardinality context fields for dashboards and filtering. Good examples
are `screen_name`, `feature`, `build_type`, `device_model`, `region`, `plan`,
`service`, `environment`, and `release`.

When the Logister project is connected to the GitHub App, mobile SDKs can send
`repository`, `commit_sha`, and `branch` on events so source-aware error detail
can resolve frames to the right code. CI/CD should also POST release-to-commit
deployment records to `/api/v1/deployments` after each app distribution step,
because the deployment endpoint is the strongest signal for release history.

Avoid sending passwords, tokens, cookies, authorization headers, payment data,
request bodies, raw local variables, or other sensitive user data.

## Package Release Notes

Android releases are tag-driven:

```bash
git tag v0.3.0
git push origin v0.3.0
```

The Android GitHub Actions release workflow builds, tests, signs, and uploads
the artifact to Sonatype Central Portal with automatic Maven Central release.
The workflow also creates the matching GitHub Release after the package version
matches the tag. Version `0.3.0` adds privacy-safe automatic crash capture,
durable pre-auth delivery, and session-bound queue cleanup.

iOS releases are also tag-driven:

```bash
git tag v0.3.0
git push origin v0.3.0
```

Swift Package Manager resolves packages from the public Git repository and tag.
The iOS GitHub Actions release workflow verifies the package and creates the
matching GitHub Release; there is no separate package-manager account or secret.

## Verification

For Android, check the release workflow and Maven Central:

```bash
gh run list --repo taimoorq/logister-android --limit 5
curl -sI https://repo1.maven.org/maven2/org/logister/logister-android/0.3.0/logister-android-0.3.0.pom
curl -sL https://repo1.maven.org/maven2/org/logister/logister-android/maven-metadata.xml
```

For iOS, check the GitHub release:

```bash
gh release view v0.3.0 --repo taimoorq/logister-ios
```
