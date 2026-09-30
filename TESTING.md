# Testing

This project uses **RSpec** for tests ([rspec-rails](https://github.com/rspec/rspec-rails)). For setup, see [README.md](README.md).

## Running tests

```bash
# All specs
bundle exec rspec

# By directory
bundle exec rspec spec/models
bundle exec rspec spec/requests
bundle exec rspec spec/services
bundle exec rspec spec/jobs
bundle exec rspec spec/routing

# Single file or example
bundle exec rspec spec/requests/home_spec.rb
bundle exec rspec spec/requests/home_spec.rb:8

# System specs only (uses Capybara + headless Chrome)
bundle exec rspec spec/system
```

Requires PostgreSQL and Redis for the test environment (same as development). Ensure `config/database.yml` and `REDIS_URL` (or default) are valid for test. System specs also require a Chrome/Chromium install (e.g. `selenium_chrome_headless`).

## Test layout

| Directory        | Purpose |
|------------------|--------|
| `spec/models`    | Model specs: validations, associations, scopes, and instance/class methods. |
| `spec/requests`  | Request (integration) specs: HTTP endpoints, auth, redirects, JSON responses. Preferred over controller specs. |
| `spec/system`    | System specs: full browser via Capybara + Selenium (headless Chrome). Use for critical user flows. |
| `spec/services`  | Service object specs: `Logister::EventIngestor`, `ErrorGroupingService`. |
| `spec/jobs`      | Job specs: enqueue, perform, and error handling. |
| `spec/routing`   | Routing specs: URL → controller/action. |
| `spec/support`   | Shared config (Devise, FactoryBot, Capybara driver). |
| `spec/fixtures`  | YAML fixtures for model, request, job, system, and service specs. |
| `spec/factories` | FactoryBot definitions (`build`, `create`, `attributes_for`) for flexible test data. |

- **Fixtures** live in `spec/fixtures` and are loaded for model, request, job, and system specs (and service specs tagged `type: :model`).
- **FactoryBot** (`factory_bot_rails`) is configured in `spec/support/factory_bot.rb`; factories in `spec/factories` provide `create`, `build`, `build_stubbed`, `attributes_for`. Use fixtures for stable shared data and factories when you need one-off or varied data.
- **Capybara + Selenium**: system specs (`spec/system/**/*_spec.rb`) use the Capybara DSL (`visit`, `fill_in`, `click_button`, etc.) and run with `selenium_chrome_headless` by default (see `spec/support/capybara.rb`).

## Coverage focus

- **Models**: Validations, associations, `accessible_to` / active / archived scopes, assignment cleanup, API key lifecycle, notification preferences, and error-group lifecycle.
- **Requests**: Public pages (home, about, legal), auth redirects, API ingest (create, auth, validation), projects CRUD and access (owner vs member), archived-project access, project events, assignment actions, dashboard, admin users, profile.
- **Services and presenters**: Event ingestor → ClickHouse payload mapping, error grouping, project event presenters, request context extraction, and language-specific stack/log rendering.
- **Jobs**: `ClickhouseIngestJob`, first-occurrence project error alerts, digest scheduling, digest delivery, and archived-project skips.
- **System specs**: Keep these focused on critical browser behavior such as auth, navigation/dropdowns, and representative Hotwire flows. Prefer request specs for the full Turbo Stream matrix.

## Conventions that keep the suite small and fast

- **Access rules live in one place.** `spec/requests/routes_protection_spec.rb` builds its list of project routes from the router. It checks that every `/projects/:uuid/...` route sends a signed-out visitor to sign in and answers someone with no access with a 404, and that a viewer can open every read-only page. A new project route is covered automatically. Do not add a per-page "requires authentication" or "returns 404 for another user's project" example. Keep an example only when it asserts more, such as a record that must not change.
- **One request spec per page or controller**, named for what it renders (`project_performance_spec.rb`, `project_monitors_spec.rb`), not one large file per resource.
- **Shell and contract checks run once per page.** `spec/requests/project_page_contract_spec.rb` renders every page for every project type. Do not re-check the header, tab bar, or current tab in feature specs.
- **Bulk data uses `insert_events`** (`spec/support/bulk_records.rb`) when the number of rows is the point. A factory per row is slow, and each event built by default also builds its own API key.
- **Query counts use `capture_sql`** (`spec/support/sql_capture.rb`), not a hand-written `sql.active_record` subscriber, unless a spec needs to filter on the SQL text or its binds.
- **Factories are linted as a whole.** `spec/models/factory_bot_spec.rb` builds every factory and trait, so a broken trait fails one example. Keep only behavior examples there, such as how a factory links records.
- **Repeated examples that differ only by data are generated from a table** (`{ "python" => [...] }.each`), so each row stays a separate example with its own name.
- **Browser specs cover only what needs a browser**: timers, focus, Stimulus lifecycle, and layout. Server-rendered content belongs in a request spec.
- **Test errors render like production.** `config.consider_all_requests_local` is `false` in `config/environments/test.rb`, so a 404 renders the static page and not the developer exception page. That cost about 70ms per 404 across the suite.
