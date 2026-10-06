# Testing

This project uses **RSpec** for tests ([rspec-rails](https://github.com/rspec/rspec-rails)). For setup, see [README.md](README.md).

## Running tests

```bash
# Match .ruby-version before invoking Bundler (rbenv users can use rbenv exec).
bundle check
RAILS_ENV=test bin/rails db:test:prepare

# All specs
bundle exec rspec

# Daily backend run; browser coverage runs separately in CI.
bundle exec rspec --exclude-pattern 'spec/system/**/*_spec.rb'

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
RAILS_ENV=test bin/rails tailwindcss:build
bundle exec rspec spec/system

# JavaScript behavior tested without a browser
node --test spec/javascript/*_test.js

# Measure the slowest examples; replay or isolate an order-dependent failure.
bundle exec rspec --exclude-pattern 'spec/system/**/*_spec.rb' --profile 15
bundle exec rspec --seed 20261003
bundle exec rspec --seed 20261003 --bisect
bundle exec rspec --only-failures
```

Requires PostgreSQL and the `redis-server` executable: some integration examples start their own temporary Redis process. `config/database.yml` selects `logister_test`; any `DATABASE_URL` override must also point to a disposable test database. `rails_helper` rejects non-test environments before booting Rails. System specs require Chrome/Chromium and the built assets.

Examples run in random order, and Ruby's random generator uses the printed RSpec seed. Failed-example status lives in ignored `tmp/rspec-examples.txt`. CI runs the complete backend, JavaScript, and browser suites without focus filtering; an empty selection fails.

## Live integration dependencies

Most examples use doubles at external service boundaries. The real-store checks use explicit test endpoints:

| Variable | Coverage |
|----------|----------|
| `REDIS_URL` | Cache, rate-limit, Sidekiq queue, recurring scheduling, and heartbeat integration. Use a dedicated Redis database. |
| `RECOVERY_CLICKHOUSE_URL` | Killed-worker recovery, replay, exact payloads, counts, and checksums. Requires a local ClickHouse server with user `logister_test` and password `test-only`. |
| `LOGISTER_TEST_CLICKHOUSE_URL` | PostgreSQL/ClickHouse correlation and span parity. Credentials use `LOGISTER_TEST_CLICKHOUSE_USERNAME` / `LOGISTER_TEST_CLICKHOUSE_PASSWORD`, defaulting to `default` / an empty password. |

Both ClickHouse checks create uniquely named databases, load `docs/clickhouse_schema.sql`, and drop their databases afterwards. GitHub CI provides all three endpoints. Missing endpoints skip locally and fail when `CI` is set; configured but unreachable endpoints fail. The Apple toolchain check additionally requires macOS and Apple command-line tools, so it skips on Linux CI.

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

- **Fixtures** live in `spec/fixtures`. The `application fixtures` shared context loads the small common graph for model, request, job, and system specs (and service specs tagged `type: :model`). Other Rails specs can opt in with `include_context "application fixtures"`; use `fixtures :users, :projects` only when a genuinely smaller graph is sufficient. Rails caches fixture loads and rolls back example changes; avoid adding large generated datasets to the common graph.
- **Fixture integrity** is checked by `spec/models/fixtures_spec.rb`: model validity, linked inbox data, and rejection of orphan foreign keys. Because inserts bypass callbacks, supply complete partition references, including `latest_event_occurred_at`. The test-only PostgreSQL validator in `spec/support/partitioned_fixture_foreign_keys.rb` validates declared parent foreign keys instead of PostgreSQL's generated partition copies; review it when upgrading Rails.
- **Isolation** uses Rails transactions for both fixtures and factories. Rails' `ActiveJob::TestHelper` resets queued/performed jobs between examples, and mail deliveries are cleared before each example. Restore any changed environment variables, runtime configuration, adapters, or external data in `ensure`/`around` cleanup. The committed-data concurrency and recovery specs explicitly disable transactions and clean up their private records; do not run separate RSpec processes against the same database.
- **FactoryBot** (`factory_bot_rails`) is configured in `spec/support/factory_bot.rb`; factories in `spec/factories` provide `create`, `build`, `build_stubbed`, `attributes_for`. Use fixtures for stable shared data and factories when you need one-off or varied data.
- **Capybara + Selenium**: system specs (`spec/system/**/*_spec.rb`) use the Capybara DSL (`visit`, `fill_in`, `click_button`, etc.) and run with `logister_selenium_chrome_headless` (see `spec/support/capybara.rb`). Modern Rails shares transactional connections with the browser server; retain transactional tests rather than introducing blanket truncation.

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
- **Persist only the data a behavior needs.** Prefer `build`, plain objects, or verifying doubles when persistence is irrelevant; use `create` for queries, constraints, callbacks, and request workflows. Pass existing `project` and `api_key` associations rather than creating a new ownership graph for each telemetry row. Build lint does not exercise create callbacks, so retain the focused persisted-factory examples.
- **Keep pure Ruby specs independent.** Require `spec_helper` plus their dependencies when Rails is unnecessary; use `rails_helper` for application autoloading or database access. Avoid database setup in `before(:context)`/`before(:all)` because it escapes example transactions.
- **Test decisions and failure paths.** Prioritize tenant isolation, durable ingestion, idempotency, retries, redaction, retention/purge, notification delivery, and representative browser journeys. Association reflection and happy paths alone do not establish coverage; a line-coverage percentage also needs branch and failure-path review.
- **Repeated examples that differ only by data are generated from a table** (`{ "python" => [...] }.each`), so each row stays a separate example with its own name.
- **Browser specs cover only what needs a browser**: timers, focus, Stimulus lifecycle, and layout. Server-rendered content belongs in a request spec.
- **Browser console logs are reset before each example.** Selenium reuses the browser, so assertions about severe console errors must not inherit errors from a previous page.
- **Test errors render like production.** `config.consider_all_requests_local` is `false` in `config/environments/test.rb`, so a 404 renders the static page and not the developer exception page. That cost about 70ms per 404 across the suite.

The transaction and seed conventions follow the [RSpec Rails transaction guide](https://rspec.info/features/8-0/rspec-rails/Transactions/) and [RSpec reproducible randomization guide](https://rspec.info/features/3-13/rspec-core/command-line/randomization/).

## Audit snapshot — October 3, 2026

The final backend run passed 1,958 examples with seed `42`, all Redis/ClickHouse integrations enabled, and no skips. It took 65 seconds with temporary Ruby standard-library coverage instrumentation and CI eager loading. The browser run passed all 35 examples with seed `20261003` in 21 seconds; all seven JavaScript assertions also passed. Before instrumentation and enabling the optional stores, the baseline backend took about 50 seconds.

The backend exercised **92.2% of executable lines and 70.6% of branches** across all Ruby files under `app/`, with no uninstrumented application Ruby files. This excludes ERB, JavaScript, and execution inside child worker processes; the separate browser and JavaScript checks cover those surfaces. No coverage dependency or instrumentation was added to normal runs.

The audit fixed queued-job and browser-console leakage, incomplete fixture partition references, duplicate local CI browser runs, and CI omissions for JavaScript and ClickHouse parity. Six focused archive purge examples now cover write quiescence, retry verification, tenant isolation, legacy storage attestation, and unavailable storage generations.

Future coverage work should prioritize job failure branches (58.7% aggregate branch coverage), digest scheduling edge cases, and S3 archive version/error handling. The slowest examples exercise real crash recovery, worker capacity, and bounded query counts; preserve those checks and optimize their setup before adding parallel execution or more browser scenarios.
