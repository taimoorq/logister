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
| Project settings | `project_api_keys` | Wraps API key form + table (streams update inside it). |
| Project settings | (none) | Memberships and assignment workload counts use streams only; no frame wrapper. |

- **Inbox:** `ProjectsController#show` and `ProjectEventsController#index` detect `Turbo-Frame: project_inbox` and render only `projects/inbox_table`. Row links use `data: { turbo_frame: "error_detail" }` so the detail pane updates.
- **Error detail:** `ProjectEventsController#show` detects `Turbo-Frame: error_detail` and renders `project_events/event_detail`. Actions (resolve/ignore/archive/reopen) use Turbo Stream responses that replace `project_inbox`, `inbox_counts`, and `error_detail`.

### Turbo Streams (multi-update responses)

Used when one action should update several DOM regions:

- **Error group actions** (`ErrorGroupsController`): PATCH resolve/ignore/archive/reopen respond with `format.turbo_stream` replacing `project_inbox`, `inbox_counts`, and `error_detail`.
- **Error assignment actions** (`ErrorGroupAssignmentsController`): PATCH/DELETE assignment update the inbox table, inbox counts, and detail pane while preserving current `filter`, `q`, and `assignee` params.
- **API keys** (`ApiKeysController`): Create responds with prepend row + replace “new token” message; destroy responds with remove row. Buttons/forms use `data: { turbo_stream: true }` where needed so the request accepts Turbo Stream.
- **Project memberships** (`ProjectMembershipsController`): Create responds with append row + replace message; destroy responds with remove row and refreshes assignment workload counts when needed.

### Stimulus controllers

| Controller | Where | Role |
|------------|--------|------|
| `inbox` | Project show | Debounced search (submit form into frame), filter tab active state, row selection highlight. |
| `tabs` | Error detail (stacktrace / context / occurrences / logs) | Switch panels. |
| `local_time` | Body | Convert `<time data-local="…">` to user’s local timezone. |
| `nav` | Layout nav | Mobile menu and project/account dropdown open/close, escape and outside-click close. |
| `project_search` | Projects index | Client-side filter of project cards by name/slug. |
| `dashboard_explorer` | Dashboard | Render ECharts, fetch scoped explorer data from Rails endpoints, and connect chart selections to server summaries. |

- All JS behavior that isn’t “just a link/form” lives in a Stimulus controller; no inline scripts in the layout (except optional third-party snippets).
- Controllers are in `app/javascript/controllers/` and are loaded via importmap.

## Where things live

- **Controllers:** Standard REST; shared logic in `ApplicationController` or concerns (e.g. `ProjectInboxData`).
- **Views:** One directory per resource; partials with leading `_`; shared partials under `shared/` (e.g. `shared/widgets/_sparkline.html.erb`).
- **Partials for streams:** Rows and one-off messages used by Turbo Streams live next to the resource (e.g. `api_keys/_row.html.erb`, `project_memberships/_row.html.erb`).
- **Models:** Domain logic, scopes, and small helpers; heavy or cross-model logic in service objects under `app/services/` (e.g. `ErrorGroupingService`, `Logister::ClickhouseClient`). Keep reusable aggregates like `ProjectAssignmentSummary` small and easy to test.
- **Jobs:** Sidekiq jobs in `app/jobs/`; enqueued from controllers, models, or scheduled worker entrypoints as needed. Project error notification jobs should skip archived projects.

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

- **Public docs no longer live in the Rails app.** Canonical docs are hosted separately on `https://docs.logister.org` from the static site in `cloudflare-docs/`.
- **Rails should link out to the external docs host.** Use the shared docs URL helpers in `ApplicationHelper` / `ProjectsHelper` instead of hardcoding internal `/docs` paths in new app UI.
- **Legacy Rails docs URLs should redirect permanently.** Keep `/docs...` routes as `301` redirects so old links preserve SEO equity and do not serve duplicate content from the app.
- **The static docs are a product surface, not a markdown dump.** Update `cloudflare-docs/` pages directly when changing setup, deployment, API, or integration guidance.
- **Docs content should follow a consistent guide shape.** The preferred flow is:
  1. Short overview
  2. Prerequisites or before-you-start context
  3. Step-by-step setup or usage flow
  4. Verification section
  5. Next steps or troubleshooting
- **Keep docs hosting concerns separate from Rails concerns.** Analytics, docs robots, docs sitemap, and docs metadata for the configured docs host belong in `cloudflare-docs/`, not in the Rails layouts or gem setup.

### SEO and crawl surfaces

- **Treat the app host and docs host as separate hosts.** The official hosts are `logister.org` and `docs.logister.org`, but forks can configure their own with `LOGISTER_PUBLIC_URL` and `LOGISTER_DOCS_URL`. Each host should own its own canonical URLs, robots policy, and sitemap.
- **The Rails sitemap is intentionally app-only.** `app/views/home/sitemap.xml.builder` should include only Rails-hosted public pages like home/about/privacy/terms, not external docs URLs.
- **Use dynamic `robots.txt` for discovery across hosts.** `home#robots` advertises both the app sitemap and the docs sitemap so crawlers can discover both surfaces from the main domain. It must derive the app host from Rails URL settings / `LOGISTER_PUBLIC_URL` and the docs host from `LOGISTER_DOCS_URL`; do not reintroduce a hardcoded `public/robots.txt`.
- **Generate static docs metadata before deploy.** Run `bin/build-cloudflare-docs` when docs pages change so `cloudflare-docs/sitemap.xml` and `cloudflare-docs/robots.txt` include the current docs pages and the configured `LOGISTER_DOCS_URL`.
- **Keep `llms.txt` current with the real product shape.** `public/llms.txt` should describe the self-hosted app, supported languages, companion packages, and public docs URLs. It should not drift back to a Ruby-only description.
- **Static docs pages should carry strong metadata.** In `cloudflare-docs/`, keep page-level canonical tags, `robots`, Open Graph, Twitter tags, and JSON-LD structured data aligned with the actual audience and technology on each page.

### Hotwire, Turbo, and Stimulus

- **Cloudflare docs are plain static pages.** The Rails app links to `docs.logister.org`; do not assume the static docs have the Rails importmap, Turbo, or Stimulus runtime.
- **Keep JS boot standard.** Turbo is loaded in `app/javascript/application.js`, Stimulus controllers are registered in `app/javascript/controllers/index.js`, and layouts should use `javascript_importmap_tags`.
- **Use Stimulus for small behavior only.** Existing docs behavior such as copy buttons and nav toggles should remain Stimulus-driven or simple DOM behavior, not custom page-specific JS frameworks.
- **Prefer Stimulus actions and lifecycle over page-load JavaScript.** Attach behavior with `data-controller`, `data-action`, targets, and values. Initialize third-party UI in `connect()`, dispose it in `disconnect()`, and use `turbo:before-cache@document` to remove transient DOM before Turbo snapshots the page. See [docs/stimulus-turbo-patterns.md](docs/stimulus-turbo-patterns.md).
- **When debugging rendering, separate HTML issues from CSS issues.** First confirm the expected classes are present in the rendered HTML. Then confirm the final compiled CSS actually contains selectors for those classes. This prevents wasting time changing views when the real problem is stale or missing assets.

### Working habits that helped

- **Inspect the actual asset URL rendered in HTML.** It quickly answers whether the browser is loading fresh CSS or an old digested file.
- **Check the compiled asset, not just the source stylesheet.** When styles seem missing, inspect both `app/assets/stylesheets/application.tailwind.css` and the compiled `app/assets/builds/tailwind.css`.
- **Use request specs to lock in layout behavior.** For docs pages in particular, request specs should verify shared asset tags, importmap tags, Turbo metadata, and key content/anchors so layout regressions are easier to spot.

### Integrations and companion packages

- **Language integrations are first-class project types.** The app currently recognizes Ruby, .NET / ASP.NET Core, Python, JavaScript / TypeScript, and CFML projects. Project labels, settings copy, event presenters, and docs links should stay aligned with those supported integration kinds.
- **Client SDKs live in separate repos.** `logister-ruby`, `logister-dotnet`, `logister-python`, and `logister-js` are companion packages with their own release cycles. Do not couple their version numbers or changelogs directly to this Rails app.
- **The Rails app should explain what package to use, not re-implement package docs.** In project settings and marketing pages, point users to the canonical integration docs and package repos instead of duplicating large SDK setup guides inside the app.
- **When adding a new integration, update all discovery surfaces together.** That includes:
  - project integration labels and settings guidance
  - project event presenters and request/activity/performance copy when the language has specific event shapes
  - external docs nav and sitemap in `cloudflare-docs/`
  - `public/llms.txt` and `public/llms-full.txt`
  - `cloudflare-docs/llms.txt` and `cloudflare-docs/llms-full.txt`
  - public marketing/about copy if the supported-language story changes

### Deploy and release learnings

- **On Fly, database setup belongs in the release phase.** `fly.toml` uses `release_command = './bin/rails db:prepare'`; the web entrypoint should not also run `db:prepare` on every boot.
- **Docs deployment is independent of app deployment.** Changes under `cloudflare-docs/` ship through the Cloudflare Pages workflow, not the Rails deploy path.
- **App and package releases are separate.** This repo’s releases describe the Rails app and hosted/self-hosted product. `logister-js` and other client packages should keep their own changelog, tags, and GitHub releases.
- **A Logister app release starts from the top changelog entry.** The main app deploy workflow reads the first versioned `CHANGELOG.md` entry and publishes that GitHub Release plus container tags only when that release does not already exist. When a user asks for a new app release, add or verify a new top changelog version first; otherwise CI/deploy may pass without creating a new GitHub Release.
- **Beta app releases stay prereleases.** Hyphenated app versions such as `v2.0.0-beta.4` are intentionally published as GitHub prereleases and should not become the repository's stable `Latest` release or the `latest` container tag. Keep the stable `Latest` badge on the newest non-prerelease until a stable version such as `v2.0.0` ships.
- **A new Logister app version requires a companion-repo readiness sweep.** When the user asks to create a new version or release of Logister, also inspect `logister-ruby`, `logister-dotnet`, `logister-python`, and `logister-js` before calling the release done. Check whether each SDK already supports any new app behavior, ingestion fields, event shapes, Insights dimensions, docs, or release metadata introduced by the app change.
- **Prepare affected SDK releases in the same sweep.** If a companion package needs code or docs changes to support the app release, update its README, changelog, package version, tests, and release workflow as needed. Bump only the SDKs that changed, and leave each affected repo on `main` with a matching local version tag so its tag workflow will publish the package-manager artifact and GitHub release when pushed.
- **Keep package managers and GitHub releases aligned.** For SDK repos, a version is not ready if GitHub shows a release but RubyGems, NuGet, npm, or PyPI would not publish the same version from the release workflow. Verify the workflow publishes the package artifact first, then creates or updates the matching GitHub release, and clearly report any missing secrets or trusted-publisher setup.
- **Release complete features across every public surface.** When a feature changes ingestion, monitoring, SDK behavior, self-hosting, or release distribution, update the Rails app, Cloudflare docs, app `llms` files, docs `llms` files, sitemap/robots metadata, changelog/release notes, image registry references, package READMEs, and companion SDK versions together. A feature is not release-ready if the code works but the public docs, package surfaces, or discovery files still describe the old behavior.
- **Version and publish each affected artifact deliberately.** The Rails app, Ruby gem, .NET SDK, Python package, JavaScript package, Docker images, and optional Quay mirror have separate release mechanics. Bump only the artifacts that changed, keep their changelogs accurate, and verify their publish workflows before calling the update done.

### Helpful CLI workflow learnings

- **Use `gh` for repo configuration and release plumbing.** It is the fastest path for checking repo visibility, collaborators, Actions secrets/variables, and triggering or inspecting workflows. Prefer it over manual GitHub UI work when the change is operational and repeatable.
- **Use `wrangler` for Cloudflare Pages work.** It is the right CLI for authenticating against Cloudflare, creating Pages projects, and deploying the static docs in `cloudflare-docs/`. The docs host is operationally separate from the Rails app, so treat Wrangler usage as part of the docs deployment toolchain.
- **Use `flyctl` for runtime deploy diagnosis.** Build failures, release-command hangs, machine state, and deploy logs are easiest to reason about with `flyctl`. It is especially useful for checking whether a failed deploy is a build issue or a release/runtime issue.
- **Prefer CLIs for repeatable ops, but keep secrets out of the repo.** `gh`, `wrangler`, and `flyctl` are great for configuration and deployment, but secrets should stay in the provider secret store or GitHub Actions secrets, not in tracked files.
- **Document the required CLIs in repo-facing docs.** When a workflow depends on `gh`, `wrangler`, or `flyctl`, keep that recommendation visible in the README or the relevant static docs page so contributors do not have to rediscover the toolchain.
