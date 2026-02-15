# logister-ruby

`logister-ruby` sends application errors and custom metrics to `logister.org`.

## Install

```ruby
gem "logister-ruby"
```

## Configuration

```ruby
Logister.configure do |config|
  config.api_key = ENV.fetch("LOGISTER_API_KEY")
  config.endpoint = "https://logister.org/api/v1/ingest_events"
  config.environment = Rails.env
  config.service = Rails.application.class.module_parent_name.underscore
  config.release = ENV["RELEASE_SHA"]
end
```

## Rails auto-reporting

If Rails is present, the gem installs middleware that reports unhandled exceptions automatically.

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
