# Stimulus and Turbo Patterns

Logister's UI is server-rendered Rails with Hotwire. JavaScript should enhance the HTML that Rails renders instead of replacing it with a separate client-side app.

## Baseline pattern

- Load Turbo once from `app/javascript/application.js`.
- Register Stimulus controllers in `app/javascript/controllers/index.js`.
- Attach behavior from ERB with `data-controller`, `data-action`, `data-*-target`, and `data-*-value`.
- Prefer Stimulus actions over manual `addEventListener` calls. Use action options such as `:capture`, `:prevent`, and `:stop` when needed.
- Use `connect()` to initialize third-party UI clients, observers, intervals, or state that depends on the element being present.
- Use `disconnect()` to dispose charts, observers, timers, third-party clients, and any manual `window` or `document` listeners.

## Turbo compatibility

Turbo Drive replaces the document body during visits, and Turbo Frames replace smaller page regions. Stimulus handles those DOM changes well as long as controllers are attached to the element that owns the behavior.

- Do not initialize page behavior from `DOMContentLoaded` or `window.onload`; those do not model Turbo visits or frame updates.
- For page-level behavior, attach a controller to the rendered page wrapper.
- For frame-local behavior, attach a controller inside the `<turbo-frame>` or on the frame content that is replaced.
- For global Turbo events, prefer Stimulus global actions such as `turbo:before-cache@document->controller#method`.
- Use `turbo:before-cache` to close modals, popovers, tours, chart overlays, or other transient DOM before Turbo snapshots the page.
- When listening to `turbo:frame-load` or `turbo:before-fetch-request` at `@document`, check `event.target` so one controller does not react to another frame's request.

## Third-party libraries

Third-party JavaScript should be npm-managed and exposed through the Rails asset pipeline/importmap path.

- Add the package to `package.json` and `package-lock.json`.
- Add the package dist directory to `config/initializers/assets.rb` when Propshaft needs to serve files from `node_modules`.
- Pin browser-ready ES module imports in `config/importmap.rb`.
- Load browser-only UMD/IIFE bundles with `javascript_include_tag` from the shared layout helper, then read their `window` global from the Stimulus controller that owns the behavior.
- Keep CI aligned with those asset paths: jobs that render Rails views or precompile assets must run `npm ci` before Rails boots against npm-backed assets.
- Dispose third-party instances in `disconnect()`.

## Current examples

- `product-tour` uses Stimulus values and actions for TourGuide.js. TourGuide's UMD bundle is npm-managed, served by Propshaft, loaded by the layout as a classic deferred script, and read from `window.tourguide`. The controller starts from page-level wrappers, can auto-start on first interaction, and removes TourGuide's generated DOM in `turbo:before-cache` so Turbo snapshots stay clean.
- `performance-breakdown`, `dashboard-explorer`, and `project-insights` own ECharts instances from Stimulus controllers and dispose them in `disconnect()`.
- `frame-tabs` listens for Turbo frame events and filters by the managed frame id before updating loading state.

## Verification checklist

- Request specs should assert the expected `data-controller`, `data-action`, target, and value attributes are present in rendered HTML.
- Run `node --check` for changed controllers.
- Run focused request specs for the touched views and controllers.
- Run `bin/rails tailwindcss:build` when class names or styles changed.
- Run `SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile` when importmap or asset pipeline wiring changed, then clobber generated development assets.
