require Rails.root.join("app/services/logister/rails_request_performance_reporter")
require Rails.root.join("app/services/logister/source_context")
require Rails.root.join("app/services/logister/internal_telemetry")
require Rails.root.join("lib/logister/self_reporting_guard")
require Rails.root.join("app/services/logister/self_reporting_policy")

Rails.application.config.middleware.insert_before(0, Logister::SelfReportingGuard)

source_context = Logister::SourceContext.current

Logister.configure do |config|
  config.api_key = InstanceConfiguration.value("observability.api_key")
  config.endpoint = InstanceConfiguration.value("observability.endpoint")
  config.environment = source_context.environment
  config.service = source_context.service
  config.release = source_context.release
  config.repository = source_context.repository if config.respond_to?(:repository=)
  config.commit_sha = source_context.commit_sha if config.respond_to?(:commit_sha=)
  config.branch = source_context.branch if config.respond_to?(:branch=)

  config.enabled = true
  config.timeout_seconds = 2

  config.async = true
  config.queue_size = 1000
  config.max_retries = 3
  config.retry_base_interval = 0.5

  config.ignore_environments = []
  config.ignore_exceptions = []
  config.ignore_paths = Logister::SelfReportingGuard::REPORTING_PATHS

  Logister::SelfReportingPolicy.apply!(config)
end

logister_config = Rails.application.config.x.logister
logister_config.public_api_rate_limit_requests = InstanceConfiguration.value("authentication.public_api_rate_limit_requests")
logister_config.public_api_rate_limit_period_seconds = InstanceConfiguration.value("authentication.public_api_rate_limit_period_seconds")
logister_config.public_api_pre_auth_rate_limit_requests = InstanceConfiguration.value("authentication.public_api_pre_auth_rate_limit_requests")
logister_config.public_api_auth_failure_rate_limit_requests = InstanceConfiguration.value("authentication.public_api_auth_failure_rate_limit_requests")

Rails.application.config.after_initialize do
  Logister::RailsRequestPerformanceReporter.install!
end
