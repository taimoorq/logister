# logister-ruby

`logister-ruby` sends application errors and custom metrics to `logister.org`.

## Install

```ruby
gem "logister-ruby"
```

Then generate an initializer in Rails:

```bash
bin/rails generate logister:install
```

## Configuration

```ruby
Logister.configure do |config|
  config.api_key = ENV.fetch("LOGISTER_API_KEY")
  config.endpoint = "https://logister.org/api/v1/ingest_events"
  config.environment = Rails.env
  config.service = Rails.application.class.module_parent_name.underscore
  config.release = ENV["RELEASE_SHA"]

  # Optional richer context hooks
  config.anonymize_ip = false
  config.max_breadcrumbs = 40
  config.max_dependencies = 20
  config.capture_sql_breadcrumbs = true
  config.sql_breadcrumb_min_duration_ms = 25.0

  config.feature_flags_resolver = lambda do |request:, user:, **|
    { new_checkout: user&.respond_to?(:beta?) && user.beta? }
  end

  config.dependency_resolver = lambda do |**|
    [] # or return [{ name:, host:, method:, status:, durationMs:, kind: }]
  end
end
```

## Reliability options

```ruby
Logister.configure do |config|
  config.async = true
  config.queue_size = 1000
  config.max_retries = 3
  config.retry_base_interval = 0.5
end
```

## Filtering and redaction

```ruby
Logister.configure do |config|
  config.ignore_environments = ["development", "test"]
  config.ignore_exceptions = ["ActiveRecord::RecordNotFound"]
  config.ignore_paths = [/health/, "/up"]

  config.before_notify = lambda do |payload|
    payload[:context]&.delete("authorization")
    payload
  end
end
```

## Rails auto-reporting

If Rails is present, the gem installs middleware that reports unhandled exceptions automatically.
It also attaches richer context (trace IDs, route/response/performance info, breadcrumbs, dependency calls, and user metadata when available).

## Database load metrics (ActiveRecord)

You can capture SQL timing metrics using ActiveSupport notifications:

```ruby
Logister.configure do |config|
  config.capture_db_metrics = true
  config.db_metric_min_duration_ms = 10.0
  config.db_metric_sample_rate = 1.0
end
```

This emits metric events with `message: "db.query"` and context fields such as `duration_ms`, `name`, `sql`, and `binds_count`.

## Breadcrumbs and dependencies

You can add manual breadcrumbs and dependency calls that will be attached to captured errors:

```ruby
Logister.add_breadcrumb(
  category: "checkout",
  message: "Starting payment authorization",
  data: { order_id: 123 }
)

Logister.add_dependency(
  name: "stripe.charge",
  host: "api.stripe.com",
  method: "POST",
  status: 200,
  duration_ms: 184.7,
  kind: "http"
)
```

The gem also captures request and SQL breadcrumbs automatically in Rails.

## ActiveJob error context

Failed ActiveJob executions are auto-reported with `job` context:
- job class/id/queue/retries/schedule
- filtered job arguments (using `filter_parameters`)
- runtime/deployment metadata
- breadcrumbs/dependency calls collected during the job

## Manual reporting

```ruby
Logister.report_error(StandardError.new("Something failed"), tags: { area: "checkout" })

Logister.report_metric(
  message: "checkout.completed",
  level: "info",
  context: { duration_ms: 123 },
  tags: { region: "us-east-1" }
)
```

## Release

Use Bundler's built-in release flow:

```bash
# 1) bump version in lib/logister/version.rb
# 2) commit changes
bundle exec rake release
```

`rake release` will build the gem, create a git tag, push commits/tags, and push to RubyGems.
