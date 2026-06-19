require Rails.root.join("app/services/logister/rails_request_performance_reporter")
require Rails.root.join("app/services/logister/source_context")

boolean = ActiveModel::Type::Boolean.new
source_context = Logister::SourceContext.current
float_env = lambda do |name, default|
  Float(ENV.fetch(name, default))
rescue ArgumentError, TypeError
  default.to_f
end
integer_env = lambda do |name, default|
  Integer(ENV.fetch(name, default))
rescue ArgumentError, TypeError
  default.to_i
end

Logister.configure do |config|
  config.api_key = ENV["LOGISTER_API_KEY"]
  config.endpoint = ENV.fetch("LOGISTER_ENDPOINT", "https://logister.org/api/v1/ingest_events")
  config.environment = source_context.environment
  config.service = source_context.service
  config.release = source_context.release
  config.repository = source_context.repository if config.respond_to?(:repository=)
  config.commit_sha = source_context.commit_sha if config.respond_to?(:commit_sha=)
  config.branch = source_context.branch if config.respond_to?(:branch=)
  if config.respond_to?(:deployment_endpoint=) && ENV["LOGISTER_DEPLOYMENT_ENDPOINT"].present?
    config.deployment_endpoint = ENV["LOGISTER_DEPLOYMENT_ENDPOINT"]
  end

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
    Logister::SourceContext.enrich_payload(payload, source_context: source_context)
  end
end

logister_config = Rails.application.config.x.logister
logister_config.web_request_transactions_enabled = boolean.cast(ENV.fetch("LOGISTER_CAPTURE_WEB_REQUEST_TRANSACTIONS", "true"))
logister_config.web_request_min_duration_ms = float_env.call("LOGISTER_WEB_REQUEST_MIN_DURATION_MS", 250.0)
logister_config.web_request_log_min_duration_ms = float_env.call("LOGISTER_WEB_REQUEST_LOG_MIN_DURATION_MS", 1000.0)
logister_config.public_api_rate_limit_requests = integer_env.call("LOGISTER_PUBLIC_API_RATE_LIMIT_REQUESTS", 1200)
logister_config.public_api_rate_limit_period_seconds = integer_env.call("LOGISTER_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS", 60)
logister_config.public_api_auth_failure_rate_limit_requests = integer_env.call("LOGISTER_PUBLIC_API_AUTH_FAILURE_RATE_LIMIT_REQUESTS", 120)

Rails.application.config.after_initialize do
  Logister::RailsRequestPerformanceReporter.install!
end
