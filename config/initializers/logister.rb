require Rails.root.join("app/services/logister/rails_request_performance_reporter")

boolean = ActiveModel::Type::Boolean.new
float_env = lambda do |name, default|
  Float(ENV.fetch(name, default))
rescue ArgumentError, TypeError
  default.to_f
end

Logister.configure do |config|
  config.api_key = ENV["LOGISTER_API_KEY"]
  config.endpoint = ENV.fetch("LOGISTER_ENDPOINT", "https://logister.org/api/v1/ingest_events")
  config.environment = Rails.env
  config.service = Rails.application.class.module_parent_name.underscore
  config.release = ENV["LOGISTER_RELEASE"]

  config.enabled = true
  config.timeout_seconds = 2

  config.async = true
  config.queue_size = 1000
  config.max_retries = 3
  config.retry_base_interval = 0.5

  config.ignore_environments = []
  config.ignore_exceptions = []
  config.ignore_paths = []

  config.capture_request_spans = boolean.cast(ENV.fetch("LOGISTER_CAPTURE_REQUEST_SPANS", "true"))

  # ActiveRecord SQL instrumentation for page-load diagnosis. Query volume is
  # controlled by the duration threshold and can be disabled through ENV.
  config.capture_db_metrics = boolean.cast(ENV.fetch("LOGISTER_CAPTURE_DB_METRICS", "true"))
  config.db_metric_min_duration_ms = float_env.call("LOGISTER_DB_METRIC_MIN_DURATION_MS", 25.0)
  config.db_metric_sample_rate = float_env.call("LOGISTER_DB_METRIC_SAMPLE_RATE", 1.0)
  config.capture_sql_breadcrumbs = boolean.cast(ENV.fetch("LOGISTER_CAPTURE_SQL_BREADCRUMBS", "true"))
  config.sql_breadcrumb_min_duration_ms = float_env.call("LOGISTER_SQL_BREADCRUMB_MIN_DURATION_MS", 25.0)

  config.before_notify = lambda do |payload|
    payload
  end
end

logister_config = Rails.application.config.x.logister
logister_config.web_request_transactions_enabled = boolean.cast(ENV.fetch("LOGISTER_CAPTURE_WEB_REQUEST_TRANSACTIONS", "true"))
logister_config.web_request_min_duration_ms = float_env.call("LOGISTER_WEB_REQUEST_MIN_DURATION_MS", 250.0)
logister_config.web_request_log_min_duration_ms = float_env.call("LOGISTER_WEB_REQUEST_LOG_MIN_DURATION_MS", 1000.0)

Rails.application.config.after_initialize do
  Logister::RailsRequestPerformanceReporter.install!
end
