Logister.configure do |config|
  config.api_key = ENV['LOGISTER_API_KEY']
  config.endpoint = ENV.fetch('LOGISTER_ENDPOINT', 'https://logister.org/api/v1/ingest_events')
  config.environment = Rails.env
  config.service = Rails.application.class.module_parent_name.underscore
  config.release = ENV['LOGISTER_RELEASE']

  config.enabled = true
  config.timeout_seconds = 2

  config.async = true
  config.queue_size = 1000
  config.max_retries = 3
  config.retry_base_interval = 0.5

  config.ignore_environments = []
  config.ignore_exceptions = []
  config.ignore_paths = []

  # Optional ActiveRecord SQL instrumentation.
  config.capture_db_metrics = false
  config.db_metric_min_duration_ms = 10.0
  config.db_metric_sample_rate = 1.0

  config.before_notify = lambda do |payload|
    payload
  end
end
