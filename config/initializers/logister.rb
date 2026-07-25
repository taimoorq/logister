require Rails.root.join("app/services/logister/rails_request_performance_reporter")
require Rails.root.join("app/services/logister/source_context")
require Rails.root.join("lib/logister/self_reporting_guard")

Rails.application.config.middleware.insert_before(0, Logister::SelfReportingGuard)

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
  config.api_key = InstanceConfiguration.value("observability.api_key")
  config.endpoint = InstanceConfiguration.value("observability.endpoint")
  config.environment = source_context.environment
  config.service = source_context.service
  config.release = source_context.release
  config.repository = source_context.repository if config.respond_to?(:repository=)
  config.commit_sha = source_context.commit_sha if config.respond_to?(:commit_sha=)
  config.branch = source_context.branch if config.respond_to?(:branch=)
  if config.respond_to?(:deployment_endpoint=) && InstanceConfiguration.value("observability.deployment_endpoint").present?
    config.deployment_endpoint = InstanceConfiguration.value("observability.deployment_endpoint")
  end

  config.enabled = true
  config.timeout_seconds = 2

  config.async = true
  config.queue_size = 1000
  config.max_retries = 3
  config.retry_base_interval = 0.5

  config.ignore_environments = []
  config.ignore_exceptions = []
  config.ignore_paths = Logister::SelfReportingGuard::REPORTING_PATHS

  config.capture_request_spans = InstanceConfiguration.value("observability.capture_request_spans")

  # ActiveRecord SQL instrumentation for page-load diagnosis. Keep the default
  # aligned with the slow-request threshold so dogfooding does not turn routine
  # queries into a burst of follow-up ingest requests.
  config.capture_db_metrics = InstanceConfiguration.value("observability.capture_db_metrics")
  config.db_metric_min_duration_ms = InstanceConfiguration.value("observability.db_metric_min_duration_ms").to_f
  config.db_metric_sample_rate = InstanceConfiguration.value("observability.db_metric_sample_rate").to_f
  config.capture_sql_breadcrumbs = InstanceConfiguration.value("observability.capture_sql_breadcrumbs")
  config.sql_breadcrumb_min_duration_ms = InstanceConfiguration.value("observability.sql_breadcrumb_min_duration_ms").to_f

  config.before_notify = lambda do |payload|
    next false if Logister::SelfReportingGuard.suppressed?

    Logister::SourceContext.enrich_payload(payload, source_context: source_context)
  end
end

logister_config = Rails.application.config.x.logister
logister_config.web_request_transactions_enabled = InstanceConfiguration.value("observability.capture_web_transactions")
logister_config.web_request_min_duration_ms = float_env.call("LOGISTER_WEB_REQUEST_MIN_DURATION_MS", 250.0)
logister_config.web_request_log_min_duration_ms = float_env.call("LOGISTER_WEB_REQUEST_LOG_MIN_DURATION_MS", 1000.0)
logister_config.public_api_rate_limit_requests = integer_env.call("LOGISTER_PUBLIC_API_RATE_LIMIT_REQUESTS", 1200)
logister_config.public_api_rate_limit_period_seconds = integer_env.call("LOGISTER_PUBLIC_API_RATE_LIMIT_PERIOD_SECONDS", 60)
logister_config.public_api_auth_failure_rate_limit_requests = integer_env.call("LOGISTER_PUBLIC_API_AUTH_FAILURE_RATE_LIMIT_REQUESTS", 120)

Rails.application.config.after_initialize do
  Logister::RailsRequestPerformanceReporter.install!
end
