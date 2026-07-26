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
    implementation("org.logister:logister-android:0.1.3")
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
    sessionTracking(true)
    installationTracking(true, rotationDays = 90)
    breadcrumbs(capacity = 50)
    offlineQueue(enabled = true, maxEvents = 30, maxBytes = 512 * 1024)
    automaticCrashCapture(true)
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

Version 0.2.0 sends a canonical, versioned mobile contract while retaining the
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
all opt-in. The installation pseudonym is random and rotated; the SDK does not
read Android ID, advertising ID, IMEI, or a hardware serial. A queued response
is not reported as accepted until a later server response succeeds.

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
    .package(url: "https://github.com/taimoorq/logister-ios.git", from: "0.1.3")
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
    defaultContext: [
        "app_version": .string("1.4.0"),
        "build_number": .string("42"),
        "device_model": .string("iPhone")
    ]
)

try await client.captureMessage(
    "Checkout opened",
    options: LogisterEventOptions(
        sessionID: "session-123",
        context: ["screen_name": .string("Checkout")]
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

iOS telemetry should include:

- `platform: "ios"`
- bundle ID as `service`
- release as app version plus build number
- `repository`, `commit_sha`, and `branch` when the app build is tied to a
  GitHub repository
- iOS version, device model, locale, and session ID when safe

The first SDK milestone is manual capture. Automatic crash breadcrumbs,
URLSession timing, retry, and offline queueing should remain opt-in until
privacy and data retention expectations are explicit.

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
git tag v0.2.0
git push origin v0.2.0
```

The Android GitHub Actions release workflow builds, tests, signs, and uploads
the artifact to Sonatype Central Portal with automatic Maven Central release.
The workflow also creates the matching GitHub Release after the package version
matches the tag. Version `0.2.0` adds the canonical Android stability contract
and app-backed collection controls.

iOS releases are also tag-driven:

```bash
git tag v0.1.3
git push origin v0.1.3
```

Swift Package Manager resolves packages from the public Git repository and tag.
The iOS GitHub Actions release workflow verifies the package and creates the
matching GitHub Release; there is no separate package-manager account or secret.

## Verification

For Android, check the release workflow and Maven Central:

```bash
gh run list --repo taimoorq/logister-android --limit 5
curl -sI https://repo1.maven.org/maven2/org/logister/logister-android/0.1.3/logister-android-0.1.3.pom
curl -sL https://repo1.maven.org/maven2/org/logister/logister-android/maven-metadata.xml
```

For iOS, check the GitHub release:

```bash
gh release view v0.1.3 --repo taimoorq/logister-ios
```
