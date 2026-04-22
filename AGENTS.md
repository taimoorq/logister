# Logister — Architecture and conventions for agents

This document describes how the app is structured so agents and contributors can follow the same patterns (Rails way, Hotwire, Turbo). For setup, deployment, and API details, see the [README](README.md).

## Rails way (DHH / Basecamp style)

- **Server-rendered HTML first.** Controllers render ERB. Use Turbo to update parts of the page without full reloads; avoid building a separate JSON API for the main UI.
- **Convention over configuration.** Stick to standard Rails naming (controllers, views, partials, `dom_id`), standard REST, and standard locations for concerns, jobs, and services.
- **One place for each concern.** Business logic in models or service objects; request/response in controllers; structure and copy in views; minimal JS in Stimulus controllers.
- **Turbo Drive everywhere by default.** Normal links and forms use Turbo (no full page reload) unless opted out with `data: { turbo: false }` (e.g. sign in / sign up for Devise).
- **Turbo Frames for “within-page” updates.** When only a section of the page should change (e.g. inbox list, error detail, API keys table), wrap that section in a `<turbo-frame id="…">` and target it from links/forms or respond with Turbo Streams.
- **Stimulus for behavior, not for data.** Use Stimulus for toggles, filters, debouncing, and small UI behavior. Keep state in the DOM or in the server response; avoid building a separate client data layer.

## Hotwire / Turbo usage

### Turbo 8 enhancements (morphing + view transitions)

When using **Turbo 8**, the layout enables:

- **View transitions** (`<meta name="turbo-view-transition" content="true">`): navigations and morphs are wrapped in the View Transitions API so the browser can crossfade/slide between states.
- **Morphing refresh** (`turbo-refresh-method: morph`, `turbo-refresh-scroll: preserve`): when a redirect returns HTML for the same page, Turbo diffs the new body and patches the DOM instead of replacing it, preserving scroll and focus.

Elements that move or appear/disappear have `view-transition-name` (and optionally `view-transition-class`) so they animate: project cards on the projects index, error rows in the inbox table, the error detail pane, and dashboard error-view cards. Custom duration is set in `application.tailwind.css` via `::view-transition-group(.project-card)` etc. On Turbo 7 these meta tags and styles are ignored (progressive enhancement).

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

## Implementation learnings

### Asset pipeline and Tailwind

- **This app uses Propshaft, not Sprockets.** Treat asset loading the Rails 8 / Propshaft way. Do not add Sprockets-style cache-busting path hacks such as `/assets/tailwind.css?v=...` unless there is a very specific reason and you have confirmed Propshaft ownership of that path.
- **Use the shared layout helpers for assets.** Both `application` and `docs` layouts should load CSS/JS through shared helpers in `ApplicationHelper` so the app has one asset-loading path:
  - `app_stylesheet_tags`
  - `app_javascript_tags`
- **Tailwind comes from `app/assets/builds/tailwind.css`.** `tailwindcss-rails` builds from `app/assets/tailwind/application.css`, which imports `app/assets/stylesheets/application.tailwind.css`. When docs or app styling changes, rebuild with `bin/rails tailwindcss:build` or run `bin/dev`.
- **Do not trust stale compiled files in `public/assets`.** If styling looks inexplicably old in development, inspect what stylesheet URL the page is loading. A stale digested CSS file can mask new styles even when `app/assets/builds/tailwind.css` is correct.
- **In development, prefer aggressive cache invalidation for asset debugging.** `config/environments/development.rb` should not set long-lived public cache headers while debugging stylesheet issues. If changes seem invisible, check the browser’s loaded CSS asset before assuming the views are wrong.

### Documentation section

- **Docs are a first-class public section, not a markdown dump.** The docs pages live in `DocsController` with a dedicated `docs` layout and public routes under `/docs`.
- **The docs layout should still follow the app’s asset and Hotwire conventions.** It may have custom chrome, but it should use the same shared stylesheet/importmap helpers and the same Turbo metadata as the main layout.
- **Critical docs structure should be visible in ERB, not hidden entirely in custom CSS.** For core layout behavior such as sidebar rail, content column, and code block framing, prefer clear template structure and utility classes so the page remains understandable even when custom CSS is being debugged.
- **Docs content should follow a consistent guide shape.** The current preferred flow is:
  1. Short overview
  2. Prerequisites or before-you-start context
  3. Step-by-step setup or usage flow
  4. Verification section
  5. Next steps or troubleshooting
- **Use the docs helpers consistently.**
  - `docs_code_block` for copyable highlighted code snippets
  - `docs_output_block` for shell output / verification blocks
  - `docs_section_items` for left-nav “On this page” anchors
  - `docs_article_classes` for the article prose shell

### Hotwire, Turbo, and Stimulus

- **Docs pages should not special-case Hotwire unless necessary.** Public docs should work as normal Turbo Drive pages. Only opt out with `data: { turbo: false }` for flows that already require full reloads, like Devise auth links.
- **Keep JS boot standard.** Turbo is loaded in `app/javascript/application.js`, Stimulus controllers are registered in `app/javascript/controllers/index.js`, and layouts should use `javascript_importmap_tags`.
- **Use Stimulus for small behavior only.** Existing docs behavior such as copy buttons and nav toggles should remain Stimulus-driven or simple DOM behavior, not custom page-specific JS frameworks.
- **When debugging rendering, separate HTML issues from CSS issues.** First confirm the expected classes are present in the rendered HTML. Then confirm the final compiled CSS actually contains selectors for those classes. This prevents wasting time changing views when the real problem is stale or missing assets.

### Working habits that helped

- **Inspect the actual asset URL rendered in HTML.** It quickly answers whether the browser is loading fresh CSS or an old digested file.
- **Check the compiled asset, not just the source stylesheet.** When styles seem missing, inspect both `app/assets/stylesheets/application.tailwind.css` and the compiled `app/assets/builds/tailwind.css`.
- **Use request specs to lock in layout behavior.** For docs pages in particular, request specs should verify shared asset tags, importmap tags, Turbo metadata, and key content/anchors so layout regressions are easier to spot.
