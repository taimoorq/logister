# Feeding CFML Data Into Logister

This guide shows how to send events from a CFML application running on Lucee or Adobe ColdFusion into Logister.

Logister does not require a CFML-specific agent. Your app can send JSON directly to the ingest API with `cfhttp`.

## What Logister accepts

Send events to:

- `POST /api/v1/ingest_events`

Authenticate with either:

- `Authorization: Bearer <api_token>`
- `X-Api-Key: <api_token>`

Supported event types:

- `error`
- `metric`
- `transaction`
- `log`
- `check_in`

Minimum useful payload:

```json
{
  "event": {
    "event_type": "error",
    "message": "Unhandled exception",
    "level": "error",
    "occurred_at": "2026-04-21T14:35:00Z",
    "context": {
      "environment": "production",
      "service": "storefront-cfml"
    }
  }
}
```

## Recommended field mapping

Use these fields consistently so Logister can group and display CFML events well:

| Logister field | CFML source | Notes |
|---|---|---|
| `event.event_type` | app-defined | Usually `error`, `transaction`, `metric`, or `log` |
| `event.message` | exception message, route name, log message | Main title shown in the UI |
| `event.level` | app-defined | `error`, `warning`, `info`, etc. |
| `event.fingerprint` | exception type + template + line | Helps group recurring errors |
| `event.occurred_at` | `now()` in UTC | ISO-8601 string |
| `event.context.environment` | env name | `production`, `staging`, etc. |
| `event.context.service` | app/service name | Example: `customer-portal-cfml` |
| `event.context.release` | deploy version | Git SHA, build number, date version |
| `event.context.request_id` | request header or generated ID | Helps correlate events |
| `event.context.trace_id` | upstream trace header | Useful when correlating with logs |
| `event.context.transaction_name` | request method + template/path | Used for transaction rollups |
| `event.context.duration_ms` | request/query timing | Used for transaction and metric charts |
| `event.context.exception.class` | `exception.type` | Exception type/class |
| `event.context.exception.backtrace` | `exception.tagContext` | Array is best |

## Event types to send from a CFML app

### `error`

Use for:

- Uncaught exceptions from `Application.cfc.onError()`
- Failed scheduled tasks
- External API failures worth surfacing as incidents

### `transaction`

Use for:

- Page request duration
- Remote CFC method duration
- Key business flow timings like checkout or sign-in

Include:

- `context.transaction_name`
- `context.duration_ms`
- `context.request_id`
- `context.trace_id`

### `metric`

Use for:

- Query timings
- HTTP client timings
- Cache timings
- Queue latency

For SQL timings, Logister already recognizes `message: "db.query"` as a useful metric convention.

### `log`

Use for:

- Structured application logs
- Audit entries
- Integration warnings

Include correlation fields when possible:

- `trace_id`
- `request_id`
- `session_id`
- `user_id`

### `check_in`

Use for:

- Cron jobs
- Scheduled feeds
- Nightly imports

These can also go to `POST /api/v1/check_ins` if you want the specialized check-in flow.

## A small CFML client

Create a reusable component to send events.

Example `LogisterClient.cfc`:

```cfml
component output="false" {
  variables.endpoint = "";
  variables.apiToken = "";
  variables.environment = "production";
  variables.service = "cfml-app";
  variables.release = "";

  public any function init(
    required string endpoint,
    required string apiToken,
    string environment = "production",
    string service = "cfml-app",
    string release = ""
  ) {
    variables.endpoint = arguments.endpoint;
    variables.apiToken = arguments.apiToken;
    variables.environment = arguments.environment;
    variables.service = arguments.service;
    variables.release = arguments.release;
    return this;
  }

  public struct function sendEvent(
    required string eventType,
    required string message,
    string level = "info",
    struct context = {},
    string fingerprint = "",
    string occurredAt = ""
  ) {
    var payload = {
      event = {
        event_type = arguments.eventType,
        message = arguments.message,
        level = arguments.level,
        context = duplicate(arguments.context)
      }
    };

    if (len(arguments.fingerprint)) {
      payload.event.fingerprint = arguments.fingerprint;
    }

    payload.event.occurred_at = len(arguments.occurredAt)
      ? arguments.occurredAt
      : dateTimeFormat(dateConvert("local2utc", now()), "yyyy-mm-dd'T'HH:nn:ss'Z'");

    if (!structKeyExists(payload.event.context, "environment")) {
      payload.event.context.environment = variables.environment;
    }

    if (!structKeyExists(payload.event.context, "service")) {
      payload.event.context.service = variables.service;
    }

    if (len(variables.release) && !structKeyExists(payload.event.context, "release")) {
      payload.event.context.release = variables.release;
    }

    cfhttp(
      url = variables.endpoint,
      method = "post",
      result = "httpResult",
      timeout = 5,
      throwOnError = false
    ) {
      cfhttpparam(type = "header", name = "Authorization", value = "Bearer " & variables.apiToken);
      cfhttpparam(type = "header", name = "Content-Type", value = "application/json");
      cfhttpparam(type = "body", value = serializeJSON(payload));
    }

    return {
      statusCode = httpResult.statusCode,
      responseBody = httpResult.fileContent
    };
  }
}
```

## Register the client in `Application.cfc`

```cfml
component {
  this.name = "my-cfml-app";

  function onApplicationStart() {
    application.logister = new path.to.LogisterClient().init(
      endpoint = "https://logister.example.com/api/v1/ingest_events",
      apiToken = server.system.environment.LOGISTER_API_TOKEN ?: "",
      environment = server.system.environment.APP_ENV ?: "production",
      service = "customer-portal-cfml",
      release = server.system.environment.APP_RELEASE ?: ""
    );

    return true;
  }
}
```

If your server does not expose environment variables that way, replace those with your own config source.

## Capture uncaught exceptions

The best first integration point is `Application.cfc.onError()`. Lucee documents `onError()` as the application lifecycle hook for uncaught exceptions.

Example:

```cfml
component {
  this.name = "my-cfml-app";

  function onApplicationStart() {
    application.logister = new path.to.LogisterClient().init(
      endpoint = "https://logister.example.com/api/v1/ingest_events",
      apiToken = "project-api-token",
      environment = "production",
      service = "customer-portal-cfml",
      release = "2026.04.21"
    );

    return true;
  }

  function onError(required struct exception, string eventName = "") {
    var frames = [];
    var fingerprint = exception.type ?: "Exception";

    if (isArray(exception.tagContext)) {
      frames = arrayMap(exception.tagContext, function(frame) {
        return (frame.template ?: "unknown") & ":" & (frame.line ?: 0);
      });

      if (arrayLen(exception.tagContext)) {
        fingerprint &= ":" & (exception.tagContext[1].template ?: "unknown");
        fingerprint &= ":" & (exception.tagContext[1].line ?: 0);
      }
    }

    application.logister.sendEvent(
      eventType = "error",
      level = "error",
      message = exception.message ?: "Unhandled CFML exception",
      fingerprint = fingerprint,
      context = {
        event_name = arguments.eventName,
        exception = {
          class = exception.type ?: "Exception",
          message = exception.message ?: "",
          detail = exception.detail ?: "",
          stacktrace = exception.stackTrace ?: "",
          backtrace = frames
        },
        cgi = {
          script_name = cgi.script_name ?: "",
          request_method = cgi.request_method ?: "",
          query_string = cgi.query_string ?: "",
          remote_addr = cgi.remote_addr ?: "",
          http_user_agent = cgi.http_user_agent ?: ""
        },
        url = duplicate(url),
        form = duplicate(form)
      }
    );
  }
}
```

## Capture request timings as transactions

Wrap important requests or business flows and send `transaction` events.

```cfml
<cfscript>
startTick = getTickCount();
statusCode = 200;

try {
  include "checkout.cfm";
  statusCode = getPageContext().getResponse().getStatus();
}
catch (any e) {
  statusCode = 500;
  rethrow;
}
finally {
  application.logister.sendEvent(
    eventType = "transaction",
    level = statusCode >= 500 ? "error" : "info",
    message = cgi.request_method & " " & cgi.script_name,
    context = {
      transaction_name = cgi.request_method & " " & cgi.script_name,
      duration_ms = getTickCount() - startTick,
      status = statusCode,
      request_id = cgi.http_x_request_id ?: "",
      trace_id = cgi.http_x_trace_id ?: ""
    }
  );
}
</cfscript>
```

## Capture query timings as metrics

Send database timing data as `metric` events.

```cfml
<cfscript>
queryStart = getTickCount();

result = queryExecute(
  "SELECT id, email FROM users WHERE id = :id",
  { id = { value = userId, cfsqltype = "cf_sql_integer" } },
  { datasource = application.datasource }
);

application.logister.sendEvent(
  eventType = "metric",
  level = "info",
  message = "db.query",
  context = {
    duration_ms = getTickCount() - queryStart,
    name = "users.by_id",
    sql = "SELECT id, email FROM users WHERE id = :id",
    datasource = application.datasource,
    row_count = result.recordCount ?: 0
  }
);
</cfscript>
```

## Capture HTTP client timings as metrics

```cfml
<cfscript>
httpStart = getTickCount();

cfhttp(
  url = "https://api.example.com/orders",
  method = "get",
  result = "apiResponse",
  timeout = 10,
  throwOnError = false
) {}

application.logister.sendEvent(
  eventType = "metric",
  level = left(apiResponse.statusCode, 3) == "5xx" ? "error" : "info",
  message = "http.client",
  context = {
    duration_ms = getTickCount() - httpStart,
    method = "GET",
    url = "https://api.example.com/orders",
    status = apiResponse.statusCode,
    integration = "orders-api"
  }
);
</cfscript>
```

## Capture application logs

If your app already writes structured logs, forward notable entries to Logister as `log` events.

```cfml
<cfscript>
application.logister.sendEvent(
  eventType = "log",
  level = "warning",
  message = "Payment gateway timeout",
  context = {
    trace_id = cgi.http_x_trace_id ?: "",
    request_id = cgi.http_x_request_id ?: "",
    user_id = session.userId ?: "",
    gateway = "stripe",
    timeout_ms = 3000
  }
);
</cfscript>
```

## Scheduled jobs and feeds

For recurring jobs, you have two good options:

1. Send a normal `check_in` event through `/api/v1/ingest_events`
2. Use the dedicated `POST /api/v1/check_ins` endpoint

The dedicated check-in endpoint is the cleaner choice for cron-like workflows.

Example:

```json
{
  "check_in": {
    "slug": "nightly-catalog-sync",
    "status": "ok",
    "expected_interval_seconds": 3600,
    "environment": "production",
    "release": "2026.04.21"
  }
}
```

## Practical rollout plan

Start small and add richer telemetry in stages:

1. Capture uncaught exceptions in `onError()`
2. Add request timing for your most important routes
3. Add `db.query` metrics for slow or high-volume queries
4. Forward high-value structured logs
5. Add check-ins for scheduled jobs

## Troubleshooting

### 401 Unauthorized

Usually means:

- Wrong API token
- Missing `Authorization: Bearer ...` header
- Token belongs to a different project/environment than expected

### 422 Unprocessable Content

Usually means the event payload is missing required fields.

At minimum, ensure:

- `event.event_type`
- `event.message`
- `event.occurred_at`

### Events arrive but charts stay empty

Check that:

- `transaction` events include `context.duration_ms`
- `transaction` events include `context.transaction_name`
- `metric` events include `context.duration_ms`
- `error` events include exception details in `context.exception`

### Duplicate noise

Add or improve:

- `fingerprint`
- `context.release`
- `context.environment`

## Notes for Lucee 7

The Lucee 7 documentation confirms a few relevant points for this integration:

- `Application.cfc.onError()` is the standard uncaught exception hook
- `cfhttp` is the built-in way to send HTTP requests
- `serializeJSON()` is the right tool for JSON payloads

Useful Lucee docs:

- Lucee 7 overview: https://docs.lucee.org/guides/lucee-7.html
- `Application.cfc` lifecycle guide: https://docs.lucee.org/recipes/application-cfc.html
- `cfhttp` reference: https://docs.lucee.org/reference/tags/http.html
- `serializeJSON()` reference: https://docs.lucee.org/reference/functions/serializejson.html
