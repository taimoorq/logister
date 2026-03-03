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

- **Models**: Validations, associations, `accessible_to` / scopes, lifecycle (e.g. `ErrorGroup` resolve/ignore/reopen).
- **Requests**: Public pages (home, about, legal), auth redirects, API ingest (create, auth, validation), projects CRUD and access (owner vs member), project events, dashboard, admin users, profile.
- **Services**: Event ingestor → Clickhouse payload mapping; error grouping (create/update group, fingerprint derivation).
- **Jobs**: `ClickhouseIngestJob` delegates to `EventIngestor`, discards on missing record.

