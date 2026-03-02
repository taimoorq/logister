# Rails Architecture Review (DHH-style)

A review of the Logister app against the conventions and preferences that David Heinemeier Hansson (Rails creator) advocates: **convention over configuration**, **majestic monolith**, **Hotwire (Turbo + Stimulus)**, **server-rendered HTML first**, and **omakase** (the default stack).

---

## What’s already in good shape

### Stack and defaults
- **Rails 8**, **Propshaft**, **Tailwind**, **importmap**, **Turbo**, **Stimulus** — matches the default Rails 8 / “omakase” setup.
- **Devise** for auth, **Sidekiq** for jobs, **Postgres** — standard choices.
- **RSpec**, **fixtures**, **system tests** with Capybara — aligned with Rails testing guidance.

### Hotwire usage
- **Turbo Frames**: `project_inbox` and `error_detail` for partial updates; filter/search and event selection feel like an SPA without a JS framework.
- **Turbo Streams**: Error group actions (resolve, ignore, archive, reopen) respond with `turbo_stream` and replace the inbox list, counts, and detail pane.
- **Stimulus**: Used for focused behavior (inbox debounced search, tabs); no large JS app.

### Controllers and routing
- **RESTful resources** and clear route names; `param: :uuid` used consistently.
- **Thin action methods** where it matters: `ErrorGroupsController` delegates to the model and responds with Turbo Streams; `ApiKeysController` and `ProjectEventsController` stay small.
- **Shared behavior** in a concern: `ProjectInboxData` holds inbox filtering/counts/caching and is included only where needed.

### Models and domain logic
- **ErrorGroup** encapsulates status and lifecycle (`mark_resolved!`, `ignore!`, `archive!`, `reopen!`, `record_occurrence!`); controllers don’t manipulate status directly.
- **ErrorGroupingService** is a single-purpose object called after an event is saved — appropriate use of a service without over-abstraction.
- **User#accessible_projects** and **Project.accessible_to(user)** keep visibility rules in the model layer.
- **Scopes and enums** on `ErrorGroup` and `ErrorOccurrence` keep query logic in the model.

### API
- **API ingest** is a simple `create` action: build event, save, run grouping, enqueue job, return JSON. No extra layers.

---

## Changes recommended to align with DHH-style Rails

### 1. Use one JavaScript pipeline (importmap only)

**Current:** Gemfile includes **vite_rails** and Procfile.dev runs `vite: bin/vite dev`, but the layout uses **importmap** (`javascript_importmap_tags`). Vite is not used by the app; it adds Node and an extra process.

**Recommendation:** Remove **vite_rails** and the `vite` process from Procfile.dev. Use **importmap** as the single JS pipeline (Rails default). Delete or repurpose `app/javascript/entrypoints/application.js` if it only contains Vite examples.

**Why:** “Omakase” means one coherent stack; mixing Vite and importmap without using Vite adds complexity and confusion.

---

### 2. Use the built Tailwind asset instead of the CDN

**Current:** The layout loads Tailwind from the **CDN** (`script src="https://cdn.tailwindcss.com"`) and defines a large block of **inline** `<style type="text/tailwindcss">` with `@layer components { ... }`. The app also has **tailwindcss-rails** and `app/assets/stylesheets/application.tailwind.css`, but the built CSS is not used in the layout.

**Recommendation:**
- Move all component and utility classes from the inline `<style type="text/tailwindcss">` into `app/assets/stylesheets/application.tailwind.css` (under `@layer components` / `@layer utilities` as appropriate).
- In the layout, remove the Tailwind CDN script, the inline config script, and the inline style block.
- Add `<%= stylesheet_link_tag "tailwind", "data-turbo-track": "reload" %>` (or the correct asset name for your tailwindcss-rails build) so the app uses the built stylesheet from `app/assets/builds`.

**Why:** The default Rails + Tailwind setup is to build CSS at deploy time and serve it as a static asset. The CDN + inline style approach is useful for prototypes but not the intended production pattern; it also makes the layout heavy and duplicates what’s already in your Tailwind source file.

---

### 3. Move stats and dashboard logic into the model layer

**Current:**
- **ProjectsController** contains `build_project_stats`, `cached_project_stats`, `projects_stats_cache_version`, `build_db_stats`, and `db_duration_ms` — a lot of query and aggregation logic in the controller.
- **DashboardController** contains `dashboard_summary_for`, `dashboard_cache_version`, and `build_error_views` — again, query and presentation logic in the controller.

**Recommendation:**
- **Project stats:** Add class methods (or a scope/query object) on `Project` or a dedicated module, e.g. `Project.stats_for(project_ids)` and `Project#db_query_stats` (or `IngestEvent.db_query_stats(project)`), and keep only “fetch and assign” in the controller. Caching can stay in the controller or move to the model (e.g. a method that uses `Rails.cache`).
- **Dashboard:** Move “dashboard summary” (counts, recent event ids, error event ids) into a **model-level API**, e.g. `User#dashboard_summary` or `Dashboard.summary_for(user)`. Prefer a small number of methods on existing models over a large “Dashboard” namespace unless the logic grows further. Keep “build_error_views” as a presenter-style method that takes the loaded events (or move it to a helper/partial if it’s purely view-related).

**Why:** DHH favors “fat model, skinny controller”: controllers orchestrate and delegate; domain and query logic live in models (or small, focused objects). This also makes stats and dashboard logic easier to test and reuse.

---

### 4. Remove dead code: nav Stimulus controller

**Current:** The mobile nav is toggled by an **inline script** in the layout; the Stimulus **nav_controller.js** is no longer wired (no `data-controller="nav"`). The file is unused.

**Recommendation:** Delete `app/javascript/controllers/nav_controller.js` to avoid dead code. If you prefer a single approach later, you can either rewire the nav to Stimulus and remove the inline script, or keep the inline script and leave the controller removed.

---

### 5. Small cleanups

- **Routes:** Remove the boilerplate comment “Define your application routes per the DSL…” if you don’t find it useful.
- **ApplicationController:** `safe_cache_fetch` and `admin_user?` are fine where they are. Optionally, `safe_cache_fetch` could move to a `Concerns::Cacheable` or stay as a private method.
- **allow_browser versions: :modern:** Reasonable for a modern-only product; no change required unless you need to support older browsers.

---

## Summary table

| Area              | Status        | Action                                              |
|-------------------|---------------|-----------------------------------------------------|
| JS pipeline       | Mixed         | Remove vite_rails; use importmap only               |
| CSS pipeline      | CDN + inline  | Use built Tailwind asset; move styles to source     |
| Controller weight | Some fat      | Move project/dashboard stats to model layer         |
| Dead code         | Nav controller| Delete nav_controller.js (or rewire and drop inline) |
| Hotwire / Turbo   | Good          | Keep as is                                          |
| Models / services | Good          | Keep; add stats/summary API where suggested         |
| Routes / REST     | Good          | Optional comment cleanup                            |

---

## References

- [Rails 8 default stack](https://guides.rubyonrails.org/getting_started.html) (importmap, Turbo, Stimulus, Tailwind, Propshaft)
- [Hotwire](https://hotwired.dev/) (Turbo, Stimulus)
- [The Majestic Monolith](https://m.signalvnoise.com/the-majestic-monolith/) (Basecamp)
- [Rails Doctrine](https://rubyonrails.org/doctrine) (convention, omakase, etc.)
