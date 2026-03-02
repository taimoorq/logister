# Logister — Architecture and conventions for agents

This document describes how the app is structured so agents and contributors can follow the same patterns (Rails way, Hotwire, Turbo).

## Rails way (DHH / Basecamp style)

- **Server-rendered HTML first.** Controllers render ERB. Use Turbo to update parts of the page without full reloads; avoid building a separate JSON API for the main UI.
- **Convention over configuration.** Stick to standard Rails naming (controllers, views, partials, `dom_id`), standard REST, and standard locations for concerns, jobs, and services.
- **One place for each concern.** Business logic in models or service objects; request/response in controllers; structure and copy in views; minimal JS in Stimulus controllers.
- **Turbo Drive everywhere by default.** Normal links and forms use Turbo (no full page reload) unless opted out with `data: { turbo: false }` (e.g. sign in / sign up for Devise).
- **Turbo Frames for “within-page” updates.** When only a section of the page should change (e.g. inbox list, error detail, API keys table), wrap that section in a `<turbo-frame id="…">` and target it from links/forms or respond with Turbo Streams.
- **Stimulus for behavior, not for data.** Use Stimulus for toggles, filters, debouncing, and small UI behavior. Keep state in the DOM or in the server response; avoid building a separate client data layer.

## Hotwire / Turbo usage

### Turbo Drive (app-wide)

- Enabled by default. All `<a>` and `<form>` are handled by Turbo; the main content is replaced without a full reload.
- Sign in / sign up use `data: { turbo: false }` so Devise can do full-page redirects and flash as intended.

### Turbo Frames (targeted updates)

| Place | Frame id | Purpose |
|-------|----------|--------|
| Project inbox (show) | `project_inbox` | Inbox table; filter links and search form target this. |
| Project inbox (show) | `error_detail` | Error detail pane; row links target this. |
| Project show | `project_api_keys` | Wraps API key form + table (streams update inside it). |
| Project show | (none) | Memberships use streams only; no frame wrapper. |

- **Inbox:** `ProjectsController#show` and `ProjectEventsController#index` detect `Turbo-Frame: project_inbox` and render only `projects/inbox_table`. Row links use `data: { turbo_frame: "error_detail" }` so the detail pane updates.
- **Error detail:** `ProjectEventsController#show` detects `Turbo-Frame: error_detail` and renders `project_events/event_detail`. Actions (resolve/ignore/archive/reopen) use Turbo Stream responses that replace `project_inbox`, `inbox_counts`, and `error_detail`.

### Turbo Streams (multi-update responses)

Used when one action should update several DOM regions:

- **Error group actions** (`ErrorGroupsController`): PATCH resolve/ignore/archive/reopen respond with `format.turbo_stream` replacing `project_inbox`, `inbox_counts`, and `error_detail`.
- **API keys** (`ApiKeysController`): Create responds with prepend row + replace “new token” message; destroy responds with remove row. Buttons/forms use `data: { turbo_stream: true }` where needed so the request accepts Turbo Stream.
- **Project memberships** (`ProjectMembershipsController`): Create responds with append row + replace message; destroy responds with remove row.

### Stimulus controllers

| Controller | Where | Role |
|------------|--------|------|
| `inbox` | Project show | Debounced search (submit form into frame), filter tab active state, row selection highlight. |
| `tabs` | Error detail (stacktrace / context / occurrences / logs) | Switch panels. |
| `local_time` | Body | Convert `<time data-local="…">` to user’s local timezone. |
| `nav` | Layout nav | Mobile menu open/close, escape and outside-click close. |
| `project_search` | Projects index | Client-side filter of project cards by name/slug. |

- All JS behavior that isn’t “just a link/form” lives in a Stimulus controller; no inline scripts in the layout (except optional third-party snippets).
- Controllers are in `app/javascript/controllers/` and are loaded via importmap.

## Where things live

- **Controllers:** Standard REST; shared logic in `ApplicationController` or concerns (e.g. `ProjectInboxData`).
- **Views:** One directory per resource; partials with leading `_`; shared partials under `shared/` (e.g. `shared/widgets/_sparkline.html.erb`).
- **Partials for streams:** Rows and one-off messages used by Turbo Streams live next to the resource (e.g. `api_keys/_row.html.erb`, `project_memberships/_row.html.erb`).
- **Models:** Domain logic, scopes, and small helpers; heavy or cross-model logic in service objects under `app/services/` (e.g. `ErrorGroupingService`, `Logister::ClickhouseClient`).
- **Jobs:** Sidekiq jobs in `app/jobs/`; enqueued from controllers or models as needed.

## Adding new “single-place” behavior

1. **Only a list or a detail pane updates:** Wrap that block in a `<turbo-frame id="unique_id">`. From elsewhere, use `data: { turbo_frame: "unique_id" }` (and optional `turbo_action: "advance"` for history). In the controller, branch on `turbo_frame_request?` and `request.headers["Turbo-Frame"]` and render the partial that contains the same frame id.
2. **One action updates several areas:** Use `respond_to format.turbo_stream` and `render turbo_stream: [ turbo_stream.replace(...), turbo_stream.prepend(...), ... ]`. Give target elements stable `id`s (often `dom_id(record)` for rows).
3. **Small UI behavior (filter, toggle, debounce):** Add a Stimulus controller and use `data-controller`, `data-action`, `data-*-target` in the view.

## Testing

- Request specs exercise controllers and Turbo: frame and stream responses are tested by hitting the same actions with the right params and headers (or by using the same URLs as the front end and asserting on response body or redirects).
- No need to duplicate full UX in system tests for every Turbo path; use request specs for “this action returns this frame/stream” and system tests for a few critical flows if desired.
